-- ShopFlow schema, Stage 2
-- PostgreSQL 14+ (tested on 16). Apply with:  psql shopflow -f db/schema.sql
--
-- Running this drops everything first, so it is safe to re-run while you
-- experiment. Never do this to a database that has real orders in it.

BEGIN;

DROP TABLE IF EXISTS order_items, orders, cart_items, carts,
                     product_images, product_variants, products,
                     categories, addresses, users CASCADE;
DROP FUNCTION IF EXISTS set_updated_at CASCADE;
DROP SEQUENCE IF EXISTS order_number_seq;


-- ---------------------------------------------------------------------------
-- Shared helper: the updated_at trigger (same one you wrote in TaskFlow)
-- ---------------------------------------------------------------------------

CREATE FUNCTION set_updated_at() RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- ---------------------------------------------------------------------------
-- users
-- ---------------------------------------------------------------------------

CREATE TABLE users (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  email         TEXT        NOT NULL,
  password_hash TEXT        NOT NULL,
  full_name     TEXT        NOT NULL DEFAULT '',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Email uniqueness is case-insensitive, because Tishad@x.com and tishad@x.com
-- are the same mailbox. A plain UNIQUE column would happily accept both and
-- you would find out when two people could not log in.
CREATE UNIQUE INDEX users_email_lower_key ON users (lower(email));

CREATE TRIGGER users_set_updated_at BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- ---------------------------------------------------------------------------
-- addresses
-- ---------------------------------------------------------------------------
-- This is the customer's ADDRESS BOOK. It is not what a shipping label is
-- printed from. See the orders table for why those must be different things.

CREATE TABLE addresses (
  id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id      BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  label        TEXT        NOT NULL DEFAULT 'Home',
  recipient    TEXT        NOT NULL,
  line1        TEXT        NOT NULL,
  line2        TEXT        NOT NULL DEFAULT '',
  city         TEXT        NOT NULL,
  region       TEXT        NOT NULL DEFAULT '',
  postal_code  TEXT        NOT NULL DEFAULT '',
  country_code CHAR(2)     NOT NULL,
  phone        TEXT        NOT NULL DEFAULT '',
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX addresses_user_id_idx ON addresses (user_id);


-- ---------------------------------------------------------------------------
-- categories
-- ---------------------------------------------------------------------------

CREATE TABLE categories (
  id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  -- A category that contains other categories. The self-reference is how you
  -- get "Equipment > Grinders" without inventing a second table.
  parent_id  BIGINT      REFERENCES categories(id) ON DELETE SET NULL,
  slug       TEXT        NOT NULL UNIQUE,
  name       TEXT        NOT NULL,
  position   INT         NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT categories_slug_format CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$')
);

CREATE INDEX categories_parent_id_idx ON categories (parent_id);


-- ---------------------------------------------------------------------------
-- products
-- ---------------------------------------------------------------------------
-- A product is the thing a customer reads about: a name, a description, photos.
-- It deliberately has NO price and NO stock. Those live on the variant.

CREATE TABLE products (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  category_id BIGINT      REFERENCES categories(id) ON DELETE SET NULL,
  slug        TEXT        NOT NULL UNIQUE,
  name        TEXT        NOT NULL,
  description TEXT        NOT NULL DEFAULT '',
  is_active   BOOLEAN     NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT products_name_not_blank CHECK (btrim(name) <> ''),
  CONSTRAINT products_slug_format    CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$')
);

CREATE INDEX products_category_id_idx ON products (category_id);
-- A partial index: only the rows a storefront query actually looks at.
-- Smaller index, and it matches "WHERE is_active" queries exactly.
CREATE INDEX products_active_idx ON products (id) WHERE is_active;

CREATE TRIGGER products_set_updated_at BEFORE UPDATE ON products
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- ---------------------------------------------------------------------------
-- product_variants  <- price and stock live HERE
-- ---------------------------------------------------------------------------
-- "250g" and "1kg" of the same coffee are one product and two variants: two
-- prices, two stock counts, two barcodes. A shop with no options still has one
-- variant per product, and the day the shop adds sizes nothing has to be
-- rebuilt. This is the single most common schema regret in a first store.

CREATE TABLE product_variants (
  id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  product_id   BIGINT      NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  sku          TEXT        NOT NULL UNIQUE,
  name         TEXT        NOT NULL DEFAULT 'Default',

  -- Money is an integer number of the currency's smallest unit. Never NUMERIC
  -- with rounding you forgot to think about, and absolutely never a float.
  price_cents  BIGINT      NOT NULL,
  currency     CHAR(3)     NOT NULL DEFAULT 'USD',

  stock        INT         NOT NULL DEFAULT 0,
  weight_grams INT         NOT NULL DEFAULT 0,
  position     INT         NOT NULL DEFAULT 0,
  is_active    BOOLEAN     NOT NULL DEFAULT true,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- The last line of defence. Application code will also check these, but
  -- application code has bugs and the database is the thing that cannot lie.
  CONSTRAINT variants_price_positive CHECK (price_cents > 0),
  CONSTRAINT variants_stock_not_negative CHECK (stock >= 0),
  CONSTRAINT variants_currency_format CHECK (currency ~ '^[A-Z]{3}$'),

  -- Two variants of one product cannot share a name.
  CONSTRAINT variants_unique_name_per_product UNIQUE (product_id, name)
);

CREATE INDEX variants_product_id_idx ON product_variants (product_id);
CREATE INDEX variants_in_stock_idx ON product_variants (product_id) WHERE stock > 0;

CREATE TRIGGER variants_set_updated_at BEFORE UPDATE ON product_variants
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- ---------------------------------------------------------------------------
-- product_images
-- ---------------------------------------------------------------------------

CREATE TABLE product_images (
  id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  product_id BIGINT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  url        TEXT   NOT NULL,
  alt        TEXT   NOT NULL DEFAULT '',
  position   INT    NOT NULL DEFAULT 0
);

CREATE INDEX product_images_product_id_idx ON product_images (product_id, position);


-- ---------------------------------------------------------------------------
-- carts and cart_items
-- ---------------------------------------------------------------------------
-- A cart is scratch paper. It is allowed to reference live products, it is
-- allowed to go stale, and it is allowed to be thrown away. An order is the
-- opposite of all three. Keeping them in separate tables is what lets each
-- behave the way it should.

CREATE TABLE carts (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  -- NULL user_id = a guest shopping with only a browser token.
  user_id       BIGINT      REFERENCES users(id) ON DELETE CASCADE,
  session_token TEXT        NOT NULL UNIQUE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- A partial UNIQUE index: at most one cart per logged-in user, while any
-- number of guest carts (user_id IS NULL) are allowed. A plain UNIQUE would
-- treat every guest cart as a duplicate of every other, because in a UNIQUE
-- constraint NULLs do not collide but the intent here is clearer stated.
CREATE UNIQUE INDEX carts_one_per_user ON carts (user_id) WHERE user_id IS NOT NULL;

CREATE TRIGGER carts_set_updated_at BEFORE UPDATE ON carts
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE cart_items (
  id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  cart_id    BIGINT      NOT NULL REFERENCES carts(id) ON DELETE CASCADE,
  -- The cart points at the LIVE variant, on purpose. If the price changes
  -- while the item is sitting in someone's cart, they should see the new
  -- price at checkout, not a stale one.
  variant_id BIGINT      NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
  quantity   INT         NOT NULL,
  added_at   TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT cart_items_quantity_positive CHECK (quantity > 0),
  -- Adding the same variant twice bumps the quantity instead of making a
  -- second row. The constraint is what lets you write ON CONFLICT DO UPDATE.
  CONSTRAINT cart_items_one_row_per_variant UNIQUE (cart_id, variant_id)
);

CREATE INDEX cart_items_cart_id_idx ON cart_items (cart_id);


-- ---------------------------------------------------------------------------
-- orders
-- ---------------------------------------------------------------------------
-- An order is a financial record. Once placed it is a statement about what
-- happened, and nothing that happens to the catalog afterwards may change it.

CREATE SEQUENCE order_number_seq START 1001;

CREATE TABLE orders (
  id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

  -- The number a customer quotes in an email. Never expose the primary key:
  -- id 3 tells a competitor you have had three orders, and lets anyone guess
  -- that order 4 exists.
  order_number TEXT NOT NULL UNIQUE DEFAULT 'SF-' || nextval('order_number_seq'),

  -- ON DELETE RESTRICT: you cannot delete a customer who has orders. The
  -- accounts must survive the account. (For a real "delete my data" request
  -- you anonymise the user row; you do not delete the sales record.)
  user_id      BIGINT REFERENCES users(id) ON DELETE RESTRICT,
  -- Copied at checkout so a guest order still has a contact, and so changing
  -- your account email later does not rewrite old receipts.
  email        TEXT NOT NULL,

  status       TEXT NOT NULL DEFAULT 'pending',

  currency     CHAR(3) NOT NULL DEFAULT 'USD',
  subtotal_cents BIGINT NOT NULL,
  shipping_cents BIGINT NOT NULL DEFAULT 0,
  tax_cents      BIGINT NOT NULL DEFAULT 0,
  discount_cents BIGINT NOT NULL DEFAULT 0,

  -- A generated column: Postgres computes it and refuses to let anyone write
  -- it. The total can never disagree with its own parts, which is a class of
  -- bug that otherwise shows up in accounting six months later.
  total_cents  BIGINT GENERATED ALWAYS AS
                 (subtotal_cents + shipping_cents + tax_cents - discount_cents) STORED,

  -- The shipping address as it was AT CHECKOUT, not a pointer into the
  -- customer's address book. If they move house next year, last year's label
  -- must still say where the parcel actually went. JSONB because this is a
  -- frozen document, never queried field by field, never joined to.
  shipping_address JSONB NOT NULL,
  billing_address  JSONB,

  -- Stops a double-clicked checkout button from creating two orders. The Go
  -- side sends a key per attempt; the UNIQUE index does the rest. Stage 5.
  idempotency_key TEXT UNIQUE,

  placed_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- A state machine, spelled out. Anything not on this list is rejected.
  CONSTRAINT orders_status_valid CHECK (status IN
    ('pending', 'paid', 'fulfilled', 'shipped', 'delivered', 'cancelled', 'refunded')),

  CONSTRAINT orders_amounts_not_negative CHECK (
    subtotal_cents >= 0 AND shipping_cents >= 0 AND
    tax_cents >= 0 AND discount_cents >= 0),
  -- A discount may not exceed what is being discounted.
  CONSTRAINT orders_discount_within_subtotal CHECK (discount_cents <= subtotal_cents)
);

CREATE INDEX orders_user_id_idx ON orders (user_id, placed_at DESC);
CREATE INDEX orders_status_idx ON orders (status) WHERE status IN ('pending', 'paid');
CREATE INDEX orders_placed_at_idx ON orders (placed_at DESC);

CREATE TRIGGER orders_set_updated_at BEFORE UPDATE ON orders
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- ---------------------------------------------------------------------------
-- order_items  <- the whole point of Stage 2
-- ---------------------------------------------------------------------------
-- Look at what is copied here rather than referenced: the product name, the
-- variant name, the SKU, and the unit price. All of it duplicated from tables
-- that already hold it.
--
-- That duplication is not a mistake and it is not denormalisation for speed.
-- It is the difference between a receipt and a query. A receipt states what
-- was true at a moment. If this table stored only variant_id and read the
-- price through a join, then raising a price on Tuesday would silently rewrite
-- every receipt ever issued, and the books would stop balancing.
--
-- Rule of thumb: any number a customer was shown, agreed to, or was charged
-- gets copied at the moment of agreement.

CREATE TABLE order_items (
  id       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_id BIGINT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,

  -- Kept only as a "which product was this, for reordering and reporting"
  -- pointer. Nullable and SET NULL, because deleting a discontinued product
  -- must never delete the record that it was sold.
  variant_id BIGINT REFERENCES product_variants(id) ON DELETE SET NULL,

  -- The snapshot.
  product_name     TEXT   NOT NULL,
  variant_name     TEXT   NOT NULL,
  sku              TEXT   NOT NULL,
  unit_price_cents BIGINT NOT NULL,
  quantity         INT    NOT NULL,

  line_total_cents BIGINT GENERATED ALWAYS AS (unit_price_cents * quantity) STORED,

  CONSTRAINT order_items_quantity_positive CHECK (quantity > 0),
  CONSTRAINT order_items_price_positive CHECK (unit_price_cents > 0)
);

CREATE INDEX order_items_order_id_idx ON order_items (order_id);
CREATE INDEX order_items_variant_id_idx ON order_items (variant_id);

COMMIT;
