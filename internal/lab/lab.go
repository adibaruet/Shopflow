// Package lab connects the storefront to Postgres and powers the SQL Lab page.
//
// Every screen in the storefront is one SQL query. The server runs it, sends
// back the rows AND the query text, so the page can show you the SQL behind
// what you are looking at.
package lab

import (
	"context"
	"database/sql"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/stdlib"

	"shopflow/internal/httpx"
)

const maxRows = 200

// Open connects to Postgres. Override with DATABASE_URL if yours differs.
func Open(ctx context.Context) (*sql.DB, error) {
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		dsn = "host=localhost dbname=shopflow sslmode=disable" // user = your Mac username
	}
	cfg, err := pgx.ParseConfig(dsn)
	if err != nil {
		return nil, err
	}
	// Simple protocol lets schema.sql (many statements in one file) run in one call.
	cfg.DefaultQueryExecMode = pgx.QueryExecModeSimpleProtocol
	db := stdlib.OpenDB(*cfg)
	ctx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	if err := db.PingContext(ctx); err != nil {
		db.Close()
		return nil, err
	}
	return db, nil
}

type Server struct{ DB *sql.DB }

// Register mounts the lab routes. db may be nil: the routes then answer 503.
func Register(mux *http.ServeMux, db *sql.DB) {
	s := Server{DB: db}
	mux.HandleFunc("GET /api/view/{name}", s.view)
	mux.HandleFunc("POST /api/sql", s.runSQL)
	mux.HandleFunc("POST /api/reset", s.reset)
}

// Result is what every query sends back to the page.
type Result struct {
	Columns   []string `json:"columns"`
	Rows      [][]any  `json:"rows"`
	Affected  int64    `json:"affected"`
	Truncated bool     `json:"truncated,omitempty"`
	Millis    float64  `json:"ms"`
	SQL       string   `json:"sql,omitempty"`
	LabSQL    string   `json:"lab_sql,omitempty"`
	Note      string   `json:"note,omitempty"`
}

type querier interface {
	QueryContext(ctx context.Context, q string, args ...any) (*sql.Rows, error)
	ExecContext(ctx context.Context, q string, args ...any) (sql.Result, error)
}

var reReturning = regexp.MustCompile(`(?i)\breturning\b`)

func firstWord(s string) string {
	f := strings.Fields(strings.ToLower(s))
	if len(f) == 0 {
		return ""
	}
	return f[0]
}

func returnsRows(s string) bool {
	switch firstWord(s) {
	case "select", "with", "table", "values", "explain", "show":
		return true
	}
	return reReturning.MatchString(s)
}

func isReadOnly(s string) bool {
	switch firstWord(s) {
	case "select", "table", "values", "explain", "show":
		return true
	}
	return false
}

func run(ctx context.Context, q querier, stmt string, args ...any) (Result, error) {
	start := time.Now()
	res := Result{Columns: []string{}, Rows: [][]any{}}
	if returnsRows(stmt) {
		rows, err := q.QueryContext(ctx, stmt, args...)
		if err != nil {
			return res, err
		}
		defer rows.Close()
		cols, _ := rows.Columns()
		res.Columns = cols
		for rows.Next() {
			if len(res.Rows) >= maxRows {
				res.Truncated = true
				break
			}
			vals := make([]any, len(cols))
			ptrs := make([]any, len(cols))
			for i := range vals {
				ptrs[i] = &vals[i]
			}
			if err := rows.Scan(ptrs...); err != nil {
				return res, err
			}
			for i, v := range vals {
				if b, ok := v.([]byte); ok {
					vals[i] = string(b)
				}
			}
			res.Rows = append(res.Rows, vals)
		}
		if err := rows.Err(); err != nil {
			return res, err
		}
		res.Affected = int64(len(res.Rows))
	} else {
		r, err := q.ExecContext(ctx, stmt, args...)
		if err != nil {
			return res, err
		}
		res.Affected, _ = r.RowsAffected()
	}
	res.Millis = float64(time.Since(start).Microseconds()) / 1000
	return res, nil
}

func (s Server) ready(w http.ResponseWriter) bool {
	if s.DB == nil {
		httpx.WriteError(w, http.StatusServiceUnavailable,
			"Postgres is not connected. Start it, check the shopflow database exists, then restart the server.", "")
		return false
	}
	return true
}

// ---------------------------------------------------------------------------
// The SQL Lab: run whatever the learner types.
// ---------------------------------------------------------------------------

func (s Server) runSQL(w http.ResponseWriter, r *http.Request) {
	if !s.ready(w) {
		return
	}
	var in struct {
		SQL    string `json:"sql"`
		Commit bool   `json:"commit"`
	}
	if err := httpx.DecodeJSON(w, r, &in); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, err.Error(), "")
		return
	}
	stmt := strings.TrimRight(strings.TrimSpace(in.SQL), "; \n\t\r")
	if stmt == "" {
		httpx.WriteError(w, http.StatusBadRequest, "Type a SQL statement first.", "sql")
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()
	tx, err := s.DB.BeginTx(ctx, nil)
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, err.Error(), "")
		return
	}
	defer tx.Rollback() // a no-op after Commit

	tx.ExecContext(ctx, "SET LOCAL statement_timeout = '5s'")
	res, err := run(ctx, tx, stmt)
	if err != nil {
		// A SQL mistake is not a server failure: send Postgres's message back as-is.
		httpx.WriteJSON(w, http.StatusOK, map[string]any{"error": err.Error()})
		return
	}
	switch {
	case in.Commit:
		if err := tx.Commit(); err != nil {
			httpx.WriteJSON(w, http.StatusOK, map[string]any{"error": err.Error()})
			return
		}
		if !isReadOnly(stmt) {
			res.Note = "Saved to the database."
		}
	case !isReadOnly(stmt):
		res.Note = "Rolled back, nothing was saved. Turn on Keep my changes to save."
	}
	httpx.WriteJSON(w, http.StatusOK, res)
}

// reset reloads db/schema.sql and db/seed.sql (run the server from the project root).
func (s Server) reset(w http.ResponseWriter, r *http.Request) {
	if !s.ready(w) {
		return
	}
	for _, f := range []string{"db/schema.sql", "db/seed.sql"} {
		b, err := os.ReadFile(f)
		if err != nil {
			httpx.WriteError(w, http.StatusInternalServerError, "cannot read "+f+": run the server from the project folder", "")
			return
		}
		if _, err := s.DB.ExecContext(r.Context(), string(b)); err != nil {
			httpx.WriteError(w, http.StatusInternalServerError, f+": "+err.Error(), "")
			return
		}
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]string{"status": "reset"})
}

// ---------------------------------------------------------------------------
// The storefront views: each screen is one query.
// ---------------------------------------------------------------------------

type view struct {
	build func(q url.Values) (string, []any)
}

func fixed(stmt string) view {
	return view{func(url.Values) (string, []any) { return stmt, nil }}
}

var views = map[string]view{
	"categories": fixed(`SELECT slug, name
FROM categories
WHERE parent_id IS NULL
ORDER BY position`),

	"products": {productsSQL},

	"product": {func(q url.Values) (string, []any) {
		return `SELECT p.name, p.description,
       v.sku, v.name AS variant, v.price_cents, v.stock,
       (v.stock > 0) AS in_stock
FROM products p
JOIN product_variants v ON v.product_id = p.id
WHERE p.slug = $1 AND p.is_active AND v.is_active
ORDER BY v.position`, []any{q.Get("slug")}
	}},

	"cart": fixed(`SELECT p.name, v.name AS variant, v.price_cents, ci.quantity,
       v.price_cents * ci.quantity AS line_cents,
       (v.stock >= ci.quantity)    AS still_available
FROM cart_items ci
JOIN product_variants v ON v.id = ci.variant_id
JOIN products p         ON p.id = v.product_id
JOIN carts ct           ON ct.id = ci.cart_id
WHERE ct.session_token = 'demo-session-token'
ORDER BY ci.added_at`),

	"orders": fixed(`SELECT o.order_number, o.status, o.placed_at::date::text AS placed,
       oi.product_name, oi.variant_name, oi.unit_price_cents,
       oi.quantity, oi.line_total_cents, o.total_cents
FROM orders o
JOIN order_items oi ON oi.order_id = o.id
ORDER BY o.placed_at DESC, oi.id`),

	"low-stock": fixed(`SELECT p.name, v.sku, v.name AS variant, v.stock
FROM product_variants v
JOIN products p ON p.id = v.product_id
WHERE v.stock < 10 AND v.is_active
ORDER BY v.stock`),

	"best-sellers": fixed(`SELECT oi.product_name, oi.sku,
       sum(oi.quantity)         AS units_sold,
       sum(oi.line_total_cents) AS revenue_cents
FROM order_items oi
JOIN orders o ON o.id = oi.order_id
WHERE o.status IN ('paid', 'fulfilled', 'shipped', 'delivered')
GROUP BY oi.product_name, oi.sku
ORDER BY units_sold DESC`),

	"revenue": fixed(`SELECT o.placed_at::date::text AS day,
       count(*)           AS orders,
       sum(o.total_cents) AS revenue_cents
FROM orders o
WHERE o.status <> 'cancelled'
GROUP BY day
ORDER BY day DESC`),

	"schema": fixed(`SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
ORDER BY table_name, ordinal_position`),
}

// productsSQL builds the storefront query. Only the filters you switch on are
// added, and values travel as $1, $2 ... parameters, never glued into the text.
func productsSQL(q url.Values) (string, []any) {
	where := []string{"p.is_active"}
	var args []any
	add := func(cond string, v any) {
		args = append(args, v)
		where = append(where, fmt.Sprintf(cond, len(args)))
	}
	if c := q.Get("category"); c != "" {
		add("(c.slug = $%[1]d OR c.parent_id = (SELECT id FROM categories WHERE slug = $%[1]d))", c)
	}
	if t := strings.TrimSpace(q.Get("q")); t != "" {
		add("(p.name ILIKE $%[1]d OR p.description ILIKE $%[1]d)", "%"+t+"%")
	}
	having := ""
	if q.Get("in_stock") == "true" {
		having = "\nHAVING coalesce(sum(v.stock), 0) > 0"
	}
	return `SELECT p.slug, p.name, c.name AS category,
       min(v.price_cents)          AS from_price_cents,
       max(v.price_cents)          AS to_price_cents,
       coalesce(sum(v.stock), 0)   AS total_stock,
       count(v.id)                 AS variants,
       min(i.url)                  AS image_url
FROM products p
LEFT JOIN categories c       ON c.id = p.category_id
LEFT JOIN product_variants v ON v.product_id = p.id AND v.is_active
LEFT JOIN product_images i   ON i.product_id = p.id
WHERE ` + strings.Join(where, "\n  AND ") + `
GROUP BY p.id, p.slug, p.name, c.name` + having + `
ORDER BY p.name`, args
}

var rePlaceholder = regexp.MustCompile(`\$(\d+)`)

// inline swaps $1, $2 for the real values so the SQL can be pasted into the Lab.
func inline(stmt string, args []any) string {
	return rePlaceholder.ReplaceAllStringFunc(stmt, func(m string) string {
		n, _ := strconv.Atoi(m[1:])
		if n < 1 || n > len(args) {
			return m
		}
		return "'" + strings.ReplaceAll(fmt.Sprint(args[n-1]), "'", "''") + "'"
	})
}

func (s Server) view(w http.ResponseWriter, r *http.Request) {
	if !s.ready(w) {
		return
	}
	v, ok := views[r.PathValue("name")]
	if !ok {
		httpx.WriteError(w, http.StatusNotFound, "no such view", "")
		return
	}
	stmt, args := v.build(r.URL.Query())
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()
	res, err := run(ctx, s.DB, stmt, args...)
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, err.Error(), "")
		return
	}
	res.SQL = stmt
	res.LabSQL = inline(stmt, args)
	httpx.WriteJSON(w, http.StatusOK, res)
}
