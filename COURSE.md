# ShopFlow: learning Go and Postgres by building a store

A step-by-step project. You already know JS and you've designed a schema
once (TaskFlow, Stage 1). This course adds the two things you haven't done:
**Go as a backend language**, and **the parts of a database that only show up
when money is involved**.

**Stack:** Go (standard library first) + PostgreSQL + plain HTML/CSS/JS
**How it runs:** one stage at a time. I explain, you run it, you break it on
purpose, then you say "next" and we move on.

---

## Why an ecommerce site is a good thing to learn on

A task manager can be sloppy and nobody notices. A store cannot:

- Two customers buy the last item at the same moment. Who gets it?
- The price changes on Tuesday. What does last Monday's receipt say?
- The payment succeeds but the server crashes before the order is saved. Now what?
- A customer refreshes the checkout page. Did they just buy it twice?

Every one of those is a database problem with a real answer, and each one has
a stage below where you meet it head-on.

---

## The stages

| # | Stage | What you learn | Status |
|---|-------|----------------|--------|
| 1 | **Go and your first API** | Toolchain, modules, structs, interfaces, errors as values, `net/http`, middleware, table tests. Products served from memory, plus a working storefront page. | **delivered** |
| 2 | **The store schema** | Products, variants, inventory, carts, orders. Money as integer cents. Why an order stores a *copy* of the price and not a reference to it. Constraints that make bad data impossible. | **delivered** |
| 3 | **Go talks to Postgres** | `pgx`, connection pools, context and timeouts, `sql.NullString` and friends, config from the environment, migrations. Swap `MemStore` for `PostgresStore` and change nothing else. | not started |
| 4 | **A real catalog API** | Parameterized queries and SQL injection, pagination that survives page 900, filtering and sorting, full-text search, `EXPLAIN ANALYZE` and the index that makes it fast. | not started |
| 5 | **Accounts, cart, checkout** | bcrypt, sessions vs JWT, middleware that authenticates, and the big one: checkout as a single transaction with `SELECT ... FOR UPDATE` so the last item is sold exactly once. Idempotency keys so a double-click is not a double order. | not started |
| 6 | **The storefront** | The whole frontend: product pages, cart, checkout flow, order history. Fetch, state, and error handling in plain JS. | not started |
| 7 | **Making it real** *(optional)* | Docker Compose, environment config, structured logging, graceful deploys, a Stripe test-mode payment. | not started |

---

## Ground rules

- **Type the code, don't paste it.** You will not learn Go's error handling by
  scrolling past it 400 times.
- **Break things on purpose.** Every stage ends with a list of things to
  deliberately do wrong so you can see what the failure looks like.
- **Standard library first.** No web framework, no ORM. Go's standard library
  is genuinely enough for this, and you will understand what a framework is
  doing for you before you let one do it.
