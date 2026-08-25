# Stage 2: the store schema

**Goal:** the database behind ShopFlow. Ten tables, in Postgres, with the
constraints that make a broken store impossible rather than merely unlikely.

No Go this stage. Just SQL and psql, so you can see the shapes before they get
buried inside Go string literals in Stage 3.

**The idea to hold onto:**

> A catalog is written in the present tense. An order is written in the past
> tense. The moment you let one table serve both, you have a system that can
> rewrite history, and history is the thing customers and accountants both
> care about most.

Everything odd-looking in this schema comes out of that one sentence.

---

## 1. Get Postgres running

```bash
brew install postgresql@16
brew services start postgresql@16
```

If `psql` isn't found afterwards, Homebrew keeps versioned formulas off your
PATH. Add it:

```bash
echo 'export PATH="/opt/homebrew/opt/postgresql@16/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
psql --version
```

Then create the database and load it:

```bash
cd ~/Downloads/shopflow-stage-2
createdb shopflow
psql shopflow -f db/schema.sql
psql shopflow -f db/seed.sql
```

Have a look around:

```bash
psql shopflow
```

```
\dt                       -- list tables
\d product_variants       -- one table in full: columns, indexes, constraints
\d+ orders                -- the + adds descriptions and storage detail
\q                        -- quit
```

`\d product_variants` is worth reading slowly. Everything below is visible in
that output.

---

## 2. The ten tables

```
users ──< addresses
  │
  └──< carts ──< cart_items >── product_variants
  │                                    │
  └──< orders ──< order_items ┄┄┄┄┄┄┄┄┄┘   (dotted = deliberately weak)
                                        
categories ──< products ──< product_variants
                   └─────< product_images
```

Read `db/schema.sql` top to bottom now. It's commented. What follows is the
reasoning behind the six decisions that actually matter.

### Decision 1: price and stock live on the variant, not the product

In Stage 1, `Product` had a `PriceCents` and a `Stock`. That was a simplification
and this stage pays it off. A product is *what a customer reads*: a name, a
description, photos. A **variant** is *what a customer buys*: a SKU, a price, a
stock count, a weight.

"250g" and "1kg" of the same coffee are one product and two variants. A shop
with no options still gets one variant per product, named `Default`, and every
query in the system stays identical the day the shop adds sizes.

This is the most common schema regret in a first store. Putting the price on the
product feels simpler for about a week, and then the shop wants two sizes and
you're rewriting every query, every handler, and every order you've already taken.

### Decision 2: money is `BIGINT`, holding whole cents

Same rule you already met in Go. `18.50` becomes `1850`. Never `FLOAT` (binary
floating point cannot represent 0.10 exactly), and `NUMERIC` only if you enjoy
arguing about rounding modes. Integers add and multiply exactly, which is what
money must do.

`BIGINT` and not `INT` because `INT` tops out around 2.1 billion, which is
$21 million in cents. That's a low ceiling for a lifetime revenue figure, and
migrating a column type on a live orders table is not a fun afternoon.

### Decision 3: carts point at live prices, orders carry copies

Look at these two tables side by side.

```sql
cart_items (cart_id, variant_id, quantity)

order_items (order_id, variant_id,
             product_name, variant_name, sku, unit_price_cents, quantity)
```

`cart_items` stores no money at all. It points at the live variant, so if the
price changes while an item is sitting in someone's cart, they see the new price
at checkout. That's correct: a cart is scratch paper, and nobody has agreed to
anything yet.

`order_items` copies the name, the variant name, the SKU **and the price** out
of the catalog at the moment of purchase. That duplication is not sloppiness and
it isn't a performance trick. It's the difference between a receipt and a query.

If `order_items` stored only `variant_id` and read the price through a join,
then raising a price on Tuesday would silently change what every past receipt
says. Your revenue reports would move. A refund would compute the wrong amount.
A customer would open their order history and find a number they never agreed to.

**Rule of thumb: any value a customer was shown, agreed to, or was charged gets
copied at the moment of agreement.** That's why the shipping address is stored
on the order as JSONB rather than as a foreign key into `addresses` — when they
move house next year, last year's label must still say where the parcel went.

### Decision 4: the three `ON DELETE` behaviours, chosen per relationship

This is where a schema states its priorities out loud.

| Relationship | On delete | Why |
|---|---|---|
| `products` → `product_variants` | `CASCADE` | A variant of a deleted product is meaningless. Take it with you. |
| `carts` → `cart_items` | `CASCADE` | Cart's gone, contents are gone. It was scratch paper. |
| `orders` → `order_items` | `CASCADE` | The lines belong to the order and only to it. |
| `product_variants` → `order_items` | `SET NULL` | **Discontinuing a product must never delete the record that it was sold.** The pointer goes null; the snapshot survives. |
| `users` → `orders` | `RESTRICT` | You cannot delete a customer who has bought something. The books outlive the account. |
| `users` → `addresses` | `CASCADE` | An address book with no owner is just clutter. |
| `categories` → `products` | `SET NULL` | Deleting a category should not delete your inventory. |

The `RESTRICT` on users is the one people push back on. What about a "delete my
data" request? You **anonymise the user row** — blank the name, replace the
email with a tombstone — and keep the sales record. Deleting it wouldn't be
privacy, it'd be destroying a financial record.

### Decision 5: let the database compute what the database can compute

```sql
total_cents BIGINT GENERATED ALWAYS AS
  (subtotal_cents + shipping_cents + tax_cents - discount_cents) STORED
```

A **generated column**. Postgres computes it on every write, and refuses to let
anyone write it directly. The total can never disagree with its own parts.

Without it, someone eventually writes an `UPDATE orders SET discount_cents = ...`
that forgets to recompute the total, and nobody notices for six months.
`order_items.line_total_cents` works the same way.

### Decision 6: name your constraints

```sql
CONSTRAINT variants_price_positive CHECK (price_cents > 0)
```

Not just `CHECK (price_cents > 0)`. Unnamed constraints get auto-generated names
like `product_variants_check1`, which is what your customer will see in a 500
error, and what you'll be searching for at 2am.

Named constraints also let Go do something useful with the failure. In Stage 3
you'll catch a `pgconn.PgError`, read `.ConstraintName`, and map
`variants_stock_not_negative` to a friendly "sorry, we just sold out" instead
of a generic 500.

---

## 3. A few Postgres features worth noticing

**Case-insensitive email uniqueness:**

```sql
CREATE UNIQUE INDEX users_email_lower_key ON users (lower(email));
```

An index on an *expression*, not a column. A plain `UNIQUE (email)` happily
accepts `Tishad@x.com` and `tishad@x.com` as two accounts, and you find out when
two people can't log in.

**Partial indexes:**

```sql
CREATE INDEX orders_status_idx ON orders (status) WHERE status IN ('pending','paid');
CREATE UNIQUE INDEX carts_one_per_user ON carts (user_id) WHERE user_id IS NOT NULL;
```

Index only the rows you actually query. The orders one stays small forever even
as delivered orders pile up, because it only contains the ones still needing
attention. The carts one enforces "at most one cart per logged-in customer"
while allowing unlimited guest carts.

**`GENERATED ALWAYS AS IDENTITY`** instead of `SERIAL`. It's the SQL-standard
spelling, and unlike `SERIAL` it stops you inserting an explicit id by accident.

**Status as `TEXT` + `CHECK`,** not a Postgres `ENUM` type. Three options exist:

- `TEXT` + `CHECK` (chosen): adding a status is one `ALTER TABLE`, and the valid
  set is readable right there in the schema.
- `CREATE TYPE ... AS ENUM`: slightly smaller on disk, but removing or renaming a
  value is genuinely painful.
- A `order_statuses` lookup table: most flexible, worth it when statuses carry
  data of their own (a label, a colour, an email template).

For seven fixed values, `CHECK` is the right size of solution.

---

## 4. Run the queries

`db/queries.sql` holds every query Stage 3 will run from Go: the storefront
listing, a product page, a live-priced cart, an order read from its snapshot,
order history, and three shop reports.

Don't run the file. Open it, and paste queries one at a time into psql so you
can read each result:

```bash
psql shopflow
```

Query 1 is the one behind the grid you already built. Note the rollup: `min` and
`max` price across variants give you "from $14.50", `sum(stock)` gives you
whether *anything* is available.

Query 4 is worth staring at. It joins `orders` to `order_items` and **nothing
else**. It cannot be affected by any change to the catalog, because it never
touches the catalog. That's the whole design in one query.

---

## 5. Break it on purpose

```bash
psql shopflow -f db/break-it.sql
```

Twelve statements that must fail, then one experiment that must succeed. A wall
of red is the success condition. Verified output on a fresh database:

```
1  variants_price_positive            -- a product that costs nothing
2  variants_stock_not_negative        -- selling more than you have
3  product_variants_sku_key           -- two things with the same SKU
4  users_email_lower_key              -- same email in different capitals
5  orders_status_valid                -- a status nobody defined
6  orders_discount_within_subtotal    -- a discount larger than the order
7  "total_cents" can only be updated to DEFAULT
8  orders_user_id_fkey                -- deleting a customer who has bought
9  cart_items_quantity_positive       -- zero of something in a cart
10 carts_one_per_user                 -- a second cart for one customer
11 products_slug_format               -- a slug that won't survive a URL
12 variants_currency_format           -- lowercase currency
```

Read the messages, not just the count. Each names the constraint you hit.

### Then the part that matters

The second half of that file raises the price of the Yirgacheffe from $18.50 to
$21.00 and then deletes the product entirely. Watch what happens to order
SF-1001:

```
--- The catalog moved. The receipt did not. ---
 sku          | catalog_price      1850 -> 2100
 sku          | receipt_price      1850          <- unchanged
 order_number | subtotal | total   6100 | 7088   <- unchanged

--- Discontinue the product completely ---
 yirgacheffe_variants_left           0           <- CASCADE took the variants

--- The sale still happened. Only the pointer went NULL. ---
 variant_id | product_name          | sku         | unit_price | qty | line_total
 (null)     | Ethiopian Yirgacheffe | COF-YIR-250 |       1850 |   2 |      3700
```

The product no longer exists in the catalog. The record that it was sold, for
how much, under what name, is untouched. **That is what Stage 2 was for.**

Reset when you're done:

```bash
psql shopflow -f db/schema.sql && psql shopflow -f db/seed.sql
```

---

## 6. Exercises

1. Add a `discontinued_at TIMESTAMPTZ` to `products` and use it instead of
   deleting rows. Which of the `ON DELETE` rules above stop mattering once you
   soft-delete? Which still matter?
2. Write a query listing every product that has **no variant in stock**, so the
   storefront can grey them out in one pass instead of one query per product.
3. Add a `coupons` table (code, percent or fixed amount, expiry, usage limit)
   and a constraint that a coupon is *either* percentage *or* fixed, never both.
   Hint: `CHECK (num_nonnulls(percent_off, amount_off_cents) = 1)`.
4. Add `product_reviews` (user, product, 1-5 rating, body, created_at) with a
   constraint that one customer may review a product once. Then write the query
   that gets average rating and review count per product without making the
   storefront listing slow.
5. Harder: the current schema stores `stock` as a single mutable number. Model it
   instead as an append-only `inventory_movements` table (+50 restock, -2 sale,
   +1 return) where stock is a `sum()`. What do you gain? What do you now have to
   worry about that you didn't before? This is a real trade-off that real shops
   argue about, and Stage 5 will make the tension concrete.

---

## What's next

**Stage 3: Go talks to Postgres.** You'll connect the Stage 1 server to this
database with `pgx`, and the payoff is the `Store` interface you already have:
write a `PostgresStore` with the same five methods, change one line in
`main.go`, delete `MemStore`, and the handlers never know anything happened.

Along the way: connection pools and why one is not optional, `context` for
timeouts and cancellation, scanning nullable columns without the code turning
into soup, keeping the database password out of your source, and migrations, so
`schema.sql` stops being a file you re-run by hand.

Say **next** when you're ready.
