package catalog

import (
	"errors"
	"net/http"
	"strconv"

	"shopflow/internal/httpx"
)

// Handler turns HTTP requests into Store calls.
//
// It holds an interface, not a concrete store. That is dependency injection,
// and it is what lets Stage 3 swap in Postgres without touching this file.
type Handler struct {
	Store Store
}

// Routes returns everything this package serves, mounted under /api.
//
// Go 1.22 taught the standard ServeMux method and wildcard patterns, so
// "GET /api/products/{id}" is now built in. No router library needed.
func (h Handler) Routes() *http.ServeMux {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/products", h.list)
	mux.HandleFunc("POST /api/products", h.create)
	mux.HandleFunc("GET /api/products/{id}", h.getByID)
	mux.HandleFunc("GET /api/categories", h.categories)
	return mux
}

// listResponse wraps the array in an object.
//
// Never return a bare JSON array as a top-level response. The day you need to
// add a total count or a next-page cursor, an object has room for it and an
// array does not, and changing the shape then breaks every client.
type listResponse struct {
	Products []Product `json:"products"`
	Count    int       `json:"count"`
}

func (h Handler) list(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	f := Filter{
		Query:    q.Get("q"),
		Category: q.Get("category"),
		InStock:  q.Get("in_stock") == "true",
	}

	products, err := h.Store.List(f)
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "could not load products", "")
		return
	}

	httpx.WriteJSON(w, http.StatusOK, listResponse{Products: products, Count: len(products)})
}

func (h Handler) getByID(w http.ResponseWriter, r *http.Request) {
	// PathValue reads the {id} out of the pattern this handler was registered with.
	raw := r.PathValue("id")

	id, err := strconv.ParseInt(raw, 10, 64)
	if err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "id must be a number", "id")
		return
	}

	p, err := h.Store.Get(id)
	if err != nil {
		// errors.Is walks the chain of wrapped errors looking for this exact
		// sentinel. Comparing err.Error() against a string would work today
		// and break the moment someone adds context to the message.
		if errors.Is(err, ErrNotFound) {
			httpx.WriteError(w, http.StatusNotFound, "no product with that id", "")
			return
		}
		httpx.WriteError(w, http.StatusInternalServerError, "could not load product", "")
		return
	}

	httpx.WriteJSON(w, http.StatusOK, p)
}

// createRequest is a separate type from Product on purpose.
//
// If you decode straight into a Product, a customer can POST {"id": 999,
// "created_at": "1970-01-01..."} and set fields only the server may set.
// A dedicated input struct means the client can only send what you listed.
type createRequest struct {
	Name        string `json:"name"`
	Description string `json:"description"`
	PriceCents  int64  `json:"price_cents"`
	Currency    string `json:"currency"`
	Stock       int    `json:"stock"`
	Category    string `json:"category"`
	ImageURL    string `json:"image_url"`
}

func (h Handler) create(w http.ResponseWriter, r *http.Request) {
	var in createRequest
	if err := httpx.DecodeJSON(w, r, &in); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, err.Error(), "")
		return
	}

	if in.Currency == "" {
		in.Currency = "USD"
	}

	p, err := h.Store.Create(Product{
		Name:        in.Name,
		Description: in.Description,
		PriceCents:  in.PriceCents,
		Currency:    in.Currency,
		Stock:       in.Stock,
		Category:    in.Category,
		ImageURL:    in.ImageURL,
	})
	if err != nil {
		// errors.As checks whether the error is (or wraps) a ValidationError
		// and, if so, copies it into ve so we can read Field off it.
		var ve ValidationError
		if errors.As(err, &ve) {
			httpx.WriteError(w, http.StatusUnprocessableEntity, ve.Message, ve.Field)
			return
		}
		httpx.WriteError(w, http.StatusInternalServerError, "could not create product", "")
		return
	}

	// 201 with a Location header is what REST asks for on a successful create.
	w.Header().Set("Location", "/api/products/"+strconv.FormatInt(p.ID, 10))
	httpx.WriteJSON(w, http.StatusCreated, p)
}

func (h Handler) categories(w http.ResponseWriter, r *http.Request) {
	cats, err := h.Store.Categories()
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "could not load categories", "")
		return
	}
	if cats == nil {
		cats = []string{} // so JSON says [] and not null
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]any{"categories": cats})
}
