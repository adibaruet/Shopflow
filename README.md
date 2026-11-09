# ShopFlow ☕

**A database-driven coffee e-commerce application built with Go and PostgreSQL.**

![Go](https://img.shields.io/badge/Go-00ADD8?logo=go&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-4169E1?logo=postgresql&logoColor=white)
![Railway](https://img.shields.io/badge/Deployed%20on-Railway-0B0D0E?logo=railway&logoColor=white)
![Neon](https://img.shields.io/badge/Database-Neon-00E599)

[**Live Demo**](https://shopflow-production-3586.up.railway.app/) · [**Source Code**](https://github.com/adibaruet/Shopflow)

---

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Tech Stack](#tech-stack)
- [Architecture](#architecture)
- [Project Structure](#project-structure)
- [Database Design](#database-design)
- [Example Query](#example-query)
- [Getting Started](#getting-started)
- [SQL Lab](#sql-lab)
- [Testing](#testing)
- [Deployment](#deployment)
- [Roadmap](#roadmap)
- [Author](#author)

---

## Overview

ShopFlow is a full-stack coffee storefront and backend engineering project. It demonstrates REST API development, relational database design, SQL query execution, and safe database exploration.

Users can browse coffee, brewing equipment, grinders, and accessories through a dynamic storefront. PostgreSQL powers product views, category navigation, inventory information, and order-related reporting. An integrated **SQL Lab** lets developers inspect the SQL behind the storefront and experiment with their own queries.

---

## Features

| Area | Highlights |
|---|---|
| **Storefront** | Browse products by category, view details and variants, check prices, stock, and availability |
| **Search & Filtering** | Category filters, `ILIKE` search on name and description, in-stock filtering, price ranges |
| **Database** | Relational schema, foreign keys and constraints, indexes, parameterized queries, order price snapshots |
| **SQL Lab** | Inspect storefront SQL, run custom queries, view results and execution time, safe-by-default rollback |
| **REST API** | Catalog endpoints, `Store` interface, strict JSON validation, structured error responses |
| **Server Reliability** | Request logging, panic recovery, 1 MiB body limit, HTTP timeouts, graceful shutdown |

---

## Tech Stack

| Technology | Purpose |
|---|---|
| **Go** | Backend and REST API |
| **PostgreSQL** | Relational database |
| **pgx** | PostgreSQL driver |
| **HTML / CSS / JavaScript** | Storefront and SQL Lab interface |

---

## Architecture

ShopFlow separates the HTTP API, data access, and frontend into distinct layers:

- **Frontend:** HTML, CSS, and JavaScript for the storefront and SQL Lab.
- **Backend:** Go handles HTTP requests, catalog operations, middleware, and server lifecycle.
- **Database:** PostgreSQL stores the e-commerce data and powers storefront views.
- **Driver:** pgx provides PostgreSQL connectivity.

The catalog API depends on a `Store` interface, so the storage implementation can change without rewriting HTTP handlers.

---

## Project Structure

```text
Shopflow/
├── cmd/
│   └── server/
│       └── main.go           # Application entry point
├── db/
│   ├── schema.sql            # Table definitions, constraints, indexes
│   ├── seed.sql              # Sample data
│   ├── queries.sql           # Example queries
│   └── break-it.sql          # Constraint and integrity experiments
├── internal/
│   ├── catalog/              # Product handlers, models, and Store interface
│   ├── httpx/                # JSON helpers and middleware
│   └── lab/                  # SQL Lab execution logic
├── web/
│   ├── index.html            # Frontend
│   └── img/                  # Product images
├── COURSE.md
├── STAGE-2.md
├── go.mod
├── go.sum
└── README.md
```

---

## Database Design

| Table | Responsibility |
|---|---|
| `users` | Customer account information |
| `addresses` | Customer address book |
| `categories` | Product categories and subcategories |
| `products` | Product descriptions and information |
| `product_variants` | SKUs, prices, sizes, and stock |
| `product_images` | Product image references |
| `carts` | Shopping cart records |
| `cart_items` | Products and quantities in carts |
| `orders` | Order records, totals, and status |
| `order_items` | Historical product and price snapshots |

### Key Design Decisions

- **Variant-level pricing and stock:** one product can have multiple sizes or configurations.
- **Data integrity:** foreign keys, unique and check constraints, and indexes protect consistency.
- **Historical price snapshots:** order items preserve product names, SKUs, variant names, and unit prices at purchase time.
- **Generated columns:** PostgreSQL calculates order totals and line totals automatically.
- **Order numbering:** a database sequence generates human-readable order numbers.
- **Category hierarchy:** self-referencing relationships support nested categories.

### SQL Concepts Demonstrated

`INNER JOIN` · `LEFT JOIN` · `GROUP BY` · `HAVING` · `ORDER BY` · aggregates (`MIN`, `MAX`, `SUM`, `COUNT`) · `COALESCE` · subqueries · CTEs · parameterized queries · constraints and indexes · transactions and rollback

---

## Example Query

This query retrieves product details, category, variant pricing, stock availability, and images in a single result set.

```sql
WITH variant_summary AS (
    SELECT
        product_id,
        MIN(price_cents) AS from_price_cents,
        MAX(price_cents) AS to_price_cents,
        SUM(stock)       AS total_stock,
        COUNT(*)         AS variants
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
    COALESCE(v.to_price_cents, 0)   AS to_price_cents,
    COALESCE(v.total_stock, 0)      AS total_stock,
    COALESCE(v.variants, 0)         AS variants,
    i.image_url
FROM products p
LEFT JOIN categories c       ON c.id = p.category_id
LEFT JOIN variant_summary v  ON v.product_id = p.id
LEFT JOIN image_summary i    ON i.product_id = p.id
WHERE p.is_active
ORDER BY p.name;
```

> **Why CTEs?** Aggregating variants and images separately prevents multiple images from multiplying variant rows and inflating stock totals.

---

## Getting Started

### Prerequisites

- [Go](https://go.dev/dl/)
- [PostgreSQL](https://www.postgresql.org/download/) 14 or later
- [Git](https://git-scm.com/)

### Installation

**1. Clone the repository**

```bash
git clone https://github.com/adibaruet/Shopflow.git
cd Shopflow
```

**2. Download dependencies**

```bash
go mod download
```

**3. Start PostgreSQL** (macOS with Homebrew; adjust for your version or OS)

```bash
brew services start postgresql@17
```

**4. Create the database**

```bash
createdb shopflow
```

**5. Configure the connection**

```bash
export DATABASE_URL="postgres://postgres:password@localhost:5432/shopflow?sslmode=disable"
```

Replace the username and password with your local credentials.

**6. Initialize the schema and seed data**

```bash
psql -d shopflow -f db/schema.sql
psql -d shopflow -f db/seed.sql
```

> ⚠️ **Warning:** `schema.sql` drops and recreates the project tables. Run it only against a disposable development database.

**7. Run the application**

```bash
go run ./cmd/server
```

Open [http://127.0.0.1:8080](http://127.0.0.1:8080) in your browser.

### Configuration

| Variable | Description |
|---|---|
| `DATABASE_URL` | PostgreSQL connection string (required) |
| `SHOPFLOW_LAB` | Set to `1` to enable full SQL Lab execution (local development only) |

---

## SQL Lab

The SQL Lab is an integrated environment for exploring the database behind the storefront.

- Inspect the SQL statements that power storefront views.
- Execute custom SQL and view results, affected rows, and execution time.
- Changes are **rolled back by default**; select **Keep my changes** to commit.
- A 5-second PostgreSQL statement timeout is applied.
- Displayed results are limited to 200 rows.

To enable full execution locally:

```bash
SHOPFLOW_LAB=1 go run ./cmd/server
```

> 🔒 **Security note:** Arbitrary SQL execution and database reset endpoints are **disabled on the public deployment**. Never enable `SHOPFLOW_LAB` on a public server.

---

## Testing

```bash
go test ./...
```

---

## Deployment

ShopFlow is deployed on **Railway** (application) with **Neon** (serverless PostgreSQL).

**Live application:** https://shopflow-production-3586.up.railway.app/

```text
   User Browser
        │
        ▼
 Railway Deployment
   (Go Application)
        │  pgx
        ▼
 Neon PostgreSQL
  (Cloud Database)
```

To deploy, set `DATABASE_URL` to your Neon connection string in Railway's service variables. Keep credentials out of source control.

---

## Roadmap

- [ ] Connect the catalog API to persistent PostgreSQL storage
- [ ] Complete shopping cart operations
- [ ] Checkout and order placement workflows
- [ ] Customer authentication and authorization
- [ ] API and database integration tests
- [ ] CI/CD with GitHub Actions
- [ ] Expanded inventory and sales reporting

---

## Author

**Humaira Tasnim Adiba**
B.Sc. in Electrical and Computer Engineering, Rajshahi University of Engineering & Technology (RUET)

[GitHub: @adibaruet](https://github.com/adibaruet)

---

<p align="center"><em>ShopFlow — Building a better coffee shopping experience, one query at a time.</em></p>
