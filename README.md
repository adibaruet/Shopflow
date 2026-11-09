# ShopFlow ☕

**A database-driven coffee e-commerce application built with Go and PostgreSQL.**

ShopFlow is a full-stack e-commerce project for browsing coffee, equipment, and supplies. It features a PostgreSQL-powered storefront, dynamic product filtering, inventory information, and an integrated SQL Lab that displays the SQL queries behind the storefront.

## Features

- **Product Storefront:** Browse coffee, equipment, grinders, and accessories.
- **Dynamic Filtering:** Filter products by category and stock availability.
- **PostgreSQL Integration:** Retrieve product information directly from a relational database.
- **Inventory Management:** Display product availability and stock quantities.
- **SQL Lab:** Inspect and execute SQL queries used by the application.
- **REST API:** Go-based HTTP API for catalog operations.
- **HTTP Middleware:** Request logging, error recovery, and server timeouts.

## Tech Stack

| Technology | Purpose |
|---|---|
| Go (Golang) | Backend development |
| PostgreSQL | Relational database |
| HTML | Frontend structure |
| CSS | Frontend styling |
| JavaScript | Frontend interactions |
| SQL | Database queries and operations |

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
├── go.mod
├── go.sum
└── README.md
```

## Database

ShopFlow uses PostgreSQL to store and retrieve product information.

The database includes relational tables such as:

- `products`
- `categories`
- `product_variants`
- `product_images`

The storefront uses SQL operations including:

- JOIN
- GROUP BY
- ORDER BY
- MIN()
- MAX()
- SUM()
- COUNT()
- COALESCE()

## Getting Started

### Prerequisites

Make sure you have installed:

- Go
- PostgreSQL
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
brew services start postgresql@16
```

### 4. Create the database

```bash
createdb shopflow
```

### 5. Initialize the database

Run the schema:

```bash
psql -d shopflow -f db/schema.sql
```

Insert sample data:

```bash
psql -d shopflow -f db/seed.sql
```

### 6. Run the application

```bash
go run ./cmd/server
```

### 7. Open the application

Visit:

http://127.0.0.1:8080

## Example SQL Query

The storefront retrieves product information using a query similar to:

```sql
SELECT
    p.slug,
    p.name,
    c.name AS category,
    MIN(v.price_cents) AS from_price_cents,
    MAX(v.price_cents) AS to_price_cents,
    COALESCE(SUM(v.stock), 0) AS total_stock,
    COUNT(v.id) AS variants,
    MIN(i.url) AS image_url
FROM products p
LEFT JOIN categories c
    ON c.id = p.category_id
LEFT JOIN product_variants v
    ON v.product_id = p.id
    AND v.is_active
LEFT JOIN product_images i
    ON i.product_id = p.id
WHERE p.is_active
GROUP BY p.id, p.slug, p.name, c.name
ORDER BY p.name;
```

## Learning Objectives

This project explores:

- Backend development with Go.
- REST API design and implementation.
- Relational database design.
- PostgreSQL integration.
- SQL joins, aggregations, and filtering.
- Dynamic frontend data rendering.
- Database-backed application architecture.

## Future Improvements

- Complete shopping cart functionality.
- Order placement and order history.
- User authentication and authorization.
- Automated testing for APIs and database operations.
- Sales and inventory reporting.
- Improved application security.

## Author

**Humaira Tasnim Adiba**

B.Sc. in Electrical and Computer Engineering  
Rajshahi University of Engineering & Technology (RUET)

- GitHub: [@adibaruet](https://github.com/adibaruet)

---

*ShopFlow — Building a better coffee shopping experience, one query at a time.*
