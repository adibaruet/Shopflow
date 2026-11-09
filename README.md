# ShopFlow ☕

**A database-driven coffee e-commerce application built with Go and PostgreSQL.**

ShopFlow is a full-stack coffee storefront and backend engineering project designed to demonstrate REST API development, relational database design, SQL query execution, and safe database exploration.

The application lets users browse coffee, equipment, grinders, and accessories through a dynamic storefront. PostgreSQL powers the product views, category navigation, inventory information, and order-related reporting. An integrated SQL Lab allows developers to inspect the SQL behind the storefront and experiment with database queries.

**Live Demo:** https://shopflow-production-3586.up.railway.app/

**Source Code:** https://github.com/adibaruet/Shopflow

---

## Features

### 1. Product Storefront
- Browse coffee, brewing equipment, grinders, and accessories.
- View individual product details and available variants.
- Explore product prices, stock quantities, and availability.
- Search products by name or description.

### 2. Dynamic Product Filtering
- Filter products by category.
- Search using PostgreSQL `ILIKE`.
- Filter products based on stock availability.
- Display product price ranges and available variants.

### 3. PostgreSQL Database Integration
- Relational database schema for products, categories, variants, carts, and orders.
- Foreign keys and constraints to maintain data integrity.
- Indexes for frequently queried fields.
- Parameterized SQL queries for dynamic filtering.
- Price snapshots in order items to preserve historical purchase information.

### 4. Interactive SQL Lab
An integrated environment for exploring and executing SQL queries.

- Inspect the SQL statements powering storefront views.
- Execute custom SQL statements against PostgreSQL.
- View query results, affected rows, and execution time.
- Automatically roll back changes by default.
- Optionally commit changes using the **Keep my changes** option.
- Apply a PostgreSQL statement timeout of 5 seconds.
- Limit displayed query results to 200 rows.

The arbitrary SQL execution and database reset endpoints are disabled on the public deployment. The SQL Lab's full execution functionality is intended for local development.

### 5. Go REST API
- HTTP endpoints for catalog operations.
- Store interface to separate HTTP handlers from storage implementation.
- JSON request validation and structured error responses.
- Logging and panic-recovery middleware.

### 6. HTTP Server Reliability
- Request logging and panic recovery.
- Request body size limit of 1 MiB.
- Strict JSON validation.
- HTTP read, write, and idle timeouts.
- Graceful shutdown to allow in-flight requests to finish.

---

## Tech Stack

| Technology | Purpose |
|---|---|
| Go | Backend development and REST API |
| PostgreSQL | Relational database |
| pgx | PostgreSQL connectivity |
| SQL | Database queries and reporting |
| HTML | Frontend structure |
| CSS | Styling and layout |
| JavaScript | Frontend interactions |

---

## Architecture

ShopFlow separates the HTTP API, database operations, and frontend into distinct components.

- **Frontend:** HTML, CSS, and JavaScript provide the product storefront and SQL exploration interface.
- **Backend:** Go handles HTTP requests, catalog operations, middleware, and server lifecycle management.
- **Database:** PostgreSQL stores the relational e-commerce data and powers storefront views and SQL exploration.
- **Database driver:** pgx provides PostgreSQL connectivity.

The catalog API uses a `Store` interface, allowing the storage implementation to be changed without rewriting HTTP handlers.

---

## Project Structure

```text
Shopflow/
│
├── cmd/
│   └── server/
│       └── main.go
│
├── db/
│   ├── schema.sql
│   ├── seed.sql
│   ├── queries.sql
│   └── break-it.sql
│
├── internal/
│   ├── catalog/
│   │   ├── handler.go
│   │   ├── product.go
│   │   ├── store.go
│   │   └── product_test.go
│   │
│   ├── httpx/
│   │   ├── json.go
│   │   └── middleware.go
│   │
│   └── lab/
│       └── lab.go
│
├── web/
│   ├── index.html
│   └── img/
│
├── COURSE.md
├── STAGE-2.md
├── go.mod
├── go.sum
└── README.md
```

---

## Database Design

The PostgreSQL database uses a relational schema to represent the main components of an e-commerce application.

| Table | Responsibility |
|---|---|
| `users` | Customer account information |
| `addresses` | Customer address book |
| `categories` | Product categories and subcategories |
| `products` | Product descriptions and information |
| `product_variants` | Product SKUs, prices, sizes, and stock |
| `product_images` | Product image references |
| `carts` | Shopping cart records |
| `cart_items` | Products and quantities in carts |
| `orders` | Order records, totals, and status |
| `order_items` | Historical product and price snapshots |

### Important Database Design Decisions

- **Product variants:** Prices and stock are stored at the variant level, allowing one product to have multiple sizes or configurations.
- **Data integrity:** Foreign keys, unique constraints, check constraints, and indexes protect relational consistency.
- **Historical price snapshots:** Order items preserve product names, SKUs, variant names, and unit prices at the time of purchase.
- **Generated columns:** PostgreSQL calculates order totals and line totals automatically.
- **Order numbering:** A database sequence generates human-readable order numbers.
- **Category hierarchy:** Self-referencing category relationships support nested categories.

### SQL Concepts Demonstrated

- INNER JOIN and LEFT JOIN
- GROUP BY and HAVING
- ORDER BY
- MIN(), MAX(), SUM(), COUNT()
- COALESCE()
- Aggregate functions
- Subqueries
- Parameterized queries
- Database constraints and indexes
- Transactions and rollback

---

## Example SQL Query

The following query demonstrates how product information, category details, variant pricing, stock availability, and product images can be retrieved together.

```sql
WITH variant_summary AS (
    SELECT
        product_id,
        MIN(price_cents) AS from_price_cents,
        MAX(price_cents) AS to_price_cents,
        SUM(stock) AS total_stock,
        COUNT(*) AS variants
    FROM product_variants
    WHERE is_active
    GROUP BY product_id
),
image_summary AS (
    SELECT
        product_id,
        MIN(url) AS image_url
    FROM product_images
    GROUP BY product_id
)
SELECT
    p.slug,
    p.name,
    c.name AS category,
    COALESCE(v.from_price_cents, 0) AS from_price_cents,
    COALESCE(v.to_price_cents, 0) AS to_price_cents,
    COALESCE(v.total_stock, 0) AS total_stock,
    COALESCE(v.variants, 0) AS variants,
    i.image_url
FROM products p
LEFT JOIN categories c
    ON c.id = p.category_id
LEFT JOIN variant_summary v
    ON v.product_id = p.id
LEFT JOIN image_summary i
    ON i.product_id = p.id
WHERE p.is_active
ORDER BY p.name;
```

The separate aggregation steps prevent multiple product images from multiplying variant rows and incorrectly inflating stock totals.

---

## Getting Started

### Prerequisites

Install the following:

- Go
- PostgreSQL 14 or later
- Git

### 1. Clone the repository

```bash
git clone https://github.com/adibaruet/Shopflow.git
cd Shopflow
```

### 2. Download dependencies

```bash
go mod download
```

### 3. Start PostgreSQL

On macOS with Homebrew:

```bash
brew services start postgresql@17
```

Adjust the service name if you use a different PostgreSQL version.

### 4. Create the database

```bash
createdb shopflow
```

### 5. Configure the database connection

The application accepts a PostgreSQL connection string through `DATABASE_URL`.

Example:

```bash
export DATABASE_URL="postgres://postgres:password@localhost:5432/shopflow?sslmode=disable"
```

Replace the username and password with your local PostgreSQL credentials.

### 6. Initialize the database

Run the schema:

```bash
psql -d shopflow -f db/schema.sql
```

Insert sample data:

```bash
psql -d shopflow -f db/seed.sql
```

**Note:** The schema script drops and recreates existing project tables. Only run it against a disposable development database, not a database containing real customer orders.

### 7. Run the application

```bash
go run ./cmd/server
```

To enable the full SQL Lab locally:

```bash
SHOPFLOW_LAB=1 go run ./cmd/server
```

Do not enable arbitrary SQL execution on a public deployment.

### 8. Open the application

Visit:

http://127.0.0.1:8080

---

## Running Tests

Run the Go test suite:

```bash
go test ./...
```

---

## Future Improvements

- Connect the catalog API to persistent PostgreSQL storage.
- Implement complete shopping cart operations.
- Implement checkout and order placement workflows.
- Add customer authentication and authorization.
- Add API and database integration tests.
- Introduce automated CI/CD using GitHub Actions.
- Expand inventory and sales reporting.

---

## Author

**Humaira Tasnim Adiba**

B.Sc. in Electrical and Computer Engineering  
Rajshahi University of Engineering & Technology (RUET)

- GitHub: https://github.com/adibaruet

---

*ShopFlow — Building a better coffee shopping experience, one query at a time.*
