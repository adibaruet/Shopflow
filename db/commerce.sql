-- ShopFlow Stage 3: turning the SQL lab into a real store
-- Apply AFTER schema.sql and seed.sql:   psql shopflow -f db/commerce.sql
-- Safe to re-run. It never touches your products, users or existing orders.
--
-- What this adds
--   1. store_settings      shop rules you can change without editing code
--   2. coupons             + coupon_redemptions (who used which coupon)
--   3. orders              a few new columns (coupon, paid/shipped/delivered/cancelled times)
--   4. order_status_history  every status change, logged automatically
--   5. refunds             request -> approved -> refunded (or rejected)
--   6. policies            the text of your policy pages, stored in the database
--   7. functions           checkout_cart, cancel_order, request_refund, resolve_refund
--
-- Why functions? Checkout touches 6 tables. If it dies halfway, you must not
-- end up with stock taken but no order. A function runs as ONE transaction:
-- everything happens, or nothing does.

BEGIN;

DROP TABLE IF EXISTS coupon_redemptions, refunds, order_status_history,
                     coupons, policies, store_settings CASCADE;
DROP FUNCTION IF EXISTS checkout_cart(TEXT, TEXT, JSONB, TEXT, TEXT);
DROP FUNCTION IF EXISTS cancel_order(TEXT, BIGINT, TEXT);
DROP FUNCTION IF EXISTS request_refund(TEXT, BIGINT, TEXT);
DROP FUNCTION IF EXISTS resolve_refund(BIGINT, TEXT);
DROP FUNCTION IF EXISTS setting_int(TEXT);
DROP FUNCTION IF EXISTS orders_guard_status() CASCADE;
DROP FUNCTION IF EXISTS orders_log_status() CASCADE;


-- ---------------------------------------------------------------------------
-- 1. store_settings
-- ---------------------------------------------------------------------------

CREATE TABLE store_settings (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  note  TEXT NOT NULL DEFAULT ''
);

INSERT INTO store_settings (key, value, note) VALUES
  ('return_window_days',       '7',     'Days after delivery a customer may ask for a refund'),
  ('shipping_flat_cents',      '500',   'Flat shipping charge'),
  ('free_shipping_over_cents', '10000', 'Shipping is free when subtotal minus discount reaches this'),
  ('tax_rate_percent',         '8',     'Tax on (subtotal - discount)');

CREATE FUNCTION setting_int(p_key TEXT) RETURNS BIGINT
LANGUAGE sql STABLE AS $$
  SELECT value::BIGINT FROM store_settings WHERE key = p_key
$$;


-- ---------------------------------------------------------------------------
-- 2. coupons
-- ---------------------------------------------------------------------------
-- discount_type 'percent': discount_value is 1..100  (20 = 20% off)
-- discount_type 'fixed'  : discount_value is in cents (500 = 5.00 off)
-- Codes are stored UPPERCASE. The checkout function uppercases what the
-- customer types, so "welcome10" and "WELCOME10" are the same coupon.

CREATE TABLE coupons (
  id                 BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code               TEXT        NOT NULL UNIQUE,
  description        TEXT        NOT NULL DEFAULT '',
  discount_type      TEXT        NOT NULL,
  discount_value     BIGINT      NOT NULL,
  max_discount_cents BIGINT,                      -- cap for percent coupons (NULL = no cap)
  min_subtotal_cents BIGINT      NOT NULL DEFAULT 0,
  usage_limit        INT,                         -- total uses allowed (NULL = unlimited)
  per_user_limit     INT         NOT NULL DEFAULT 1,
  starts_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at         TIMESTAMPTZ,
  is_active          BOOLEAN     NOT NULL DEFAULT true,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT coupons_code_format     CHECK (code = upper(code) AND code ~ '^[A-Z0-9_-]{3,30}$'),
  CONSTRAINT coupons_type_valid      CHECK (discount_type IN ('percent', 'fixed')),
  CONSTRAINT coupons_value_positive  CHECK (discount_value > 0),
  CONSTRAINT coupons_percent_range   CHECK (discount_type <> 'percent' OR discount_value <= 100),
  CONSTRAINT coupons_limits_sane     CHECK (min_subtotal_cents >= 0 AND per_user_limit > 0
                                            AND (usage_limit IS NULL OR usage_limit > 0)),
  CONSTRAINT coupons_dates_sane      CHECK (expires_at IS NULL OR expires_at > starts_at)
);

-- One row per use. "How many times has this been used?" is a COUNT over this
-- table, not a counter column that can drift out of sync. When an order is
-- cancelled the row is not deleted, it gets released_at, so history survives.
CREATE TABLE coupon_redemptions (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  coupon_id      BIGINT      NOT NULL REFERENCES coupons(id) ON DELETE CASCADE,
  user_id        BIGINT      NOT NULL REFERENCES users(id)   ON DELETE CASCADE,
  order_id       BIGINT      NOT NULL UNIQUE REFERENCES orders(id) ON DELETE CASCADE,
  discount_cents BIGINT      NOT NULL,
  redeemed_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  released_at    TIMESTAMPTZ
);

CREATE INDEX coupon_redemptions_coupon_idx ON coupon_redemptions (coupon_id) WHERE released_at IS NULL;
CREATE INDEX coupon_redemptions_user_idx   ON coupon_redemptions (user_id, coupon_id);


-- ---------------------------------------------------------------------------
-- 3. orders: new columns
-- ---------------------------------------------------------------------------
-- coupon_code is a COPY of the code, for the same reason order_items copies
-- the product name: if the coupon is deleted tomorrow, the receipt must still
-- say what was applied.

ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS coupon_id     BIGINT REFERENCES coupons(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS coupon_code   TEXT,
  ADD COLUMN IF NOT EXISTS paid_at       TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS shipped_at    TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS delivered_at  TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS cancelled_at  TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS cancel_reason TEXT NOT NULL DEFAULT '';

-- Fill in the time for the order your seed already created.
UPDATE orders SET paid_at = placed_at WHERE status = 'paid' AND paid_at IS NULL;

-- A cancelled order must have a cancel time, and only a cancelled one may.
ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_cancel_consistent;
ALTER TABLE orders ADD CONSTRAINT orders_cancel_consistent
  CHECK ((status = 'cancelled') = (cancelled_at IS NOT NULL));


-- ---------------------------------------------------------------------------
-- 4. Order status rules (a state machine) and the history log
-- ---------------------------------------------------------------------------
--   pending -> paid -> fulfilled -> shipped -> delivered -> refunded
--   cancel is possible from pending / paid / fulfilled (before it ships)
--
-- The trigger also stamps paid_at / shipped_at / delivered_at / cancelled_at,
-- so no application code can forget to.

CREATE FUNCTION orders_guard_status() RETURNS trigger AS $$
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
    RETURN NEW;
  END IF;

  -- An undefined status is the CHECK constraint's job; let it name itself.
  IF NEW.status NOT IN ('pending','paid','fulfilled','shipped','delivered','cancelled','refunded') THEN
    RETURN NEW;
  END IF;

  IF NOT (
       (OLD.status = 'pending'   AND NEW.status IN ('paid', 'cancelled'))
    OR (OLD.status = 'paid'      AND NEW.status IN ('fulfilled', 'shipped', 'cancelled'))
    OR (OLD.status = 'fulfilled' AND NEW.status IN ('shipped', 'cancelled'))
    OR (OLD.status = 'shipped'   AND NEW.status = 'delivered')
    OR (OLD.status = 'delivered' AND NEW.status = 'refunded')
  ) THEN
    RAISE EXCEPTION 'order % cannot go from % to %', OLD.order_number, OLD.status, NEW.status
      USING ERRCODE = 'check_violation';
  END IF;

  IF NEW.status = 'paid'      THEN NEW.paid_at      := now(); END IF;
  IF NEW.status = 'shipped'   THEN NEW.shipped_at   := now(); END IF;
  IF NEW.status = 'delivered' THEN NEW.delivered_at := now(); END IF;
  IF NEW.status = 'cancelled' THEN NEW.cancelled_at := now(); END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER orders_guard_status BEFORE UPDATE OF status ON orders
  FOR EACH ROW EXECUTE FUNCTION orders_guard_status();

CREATE TABLE order_status_history (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_id    BIGINT      NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  from_status TEXT,
  to_status   TEXT        NOT NULL,
  changed_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX order_status_history_order_idx ON order_status_history (order_id, changed_at);

CREATE FUNCTION orders_log_status() RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO order_status_history (order_id, from_status, to_status)
    VALUES (NEW.id, NULL, NEW.status);
  ELSE
    INSERT INTO order_status_history (order_id, from_status, to_status)
    VALUES (NEW.id, OLD.status, NEW.status);
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER orders_log_status_ins AFTER INSERT ON orders
  FOR EACH ROW EXECUTE FUNCTION orders_log_status();
CREATE TRIGGER orders_log_status_upd AFTER UPDATE OF status ON orders
  FOR EACH ROW WHEN (OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION orders_log_status();

-- History for orders that already exist.
INSERT INTO order_status_history (order_id, from_status, to_status, changed_at)
SELECT id, NULL, status, placed_at FROM orders;


-- ---------------------------------------------------------------------------
-- 5. refunds
-- ---------------------------------------------------------------------------
-- requested -> approved -> refunded      (or requested -> rejected)
-- This version refunds the whole order. Partial refunds are a good Stage 4:
-- you would add a refund_items table pointing at order_items.

CREATE TABLE refunds (
  id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_id     BIGINT      NOT NULL REFERENCES orders(id) ON DELETE RESTRICT,
  amount_cents BIGINT      NOT NULL,
  reason       TEXT        NOT NULL DEFAULT '',
  status       TEXT        NOT NULL DEFAULT 'requested',
  requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved_at  TIMESTAMPTZ,

  CONSTRAINT refunds_amount_positive CHECK (amount_cents > 0),
  CONSTRAINT refunds_status_valid    CHECK (status IN ('requested','approved','rejected','refunded'))
);

-- At most ONE open refund per order, enforced by the database.
CREATE UNIQUE INDEX refunds_one_open_per_order ON refunds (order_id)
  WHERE status IN ('requested', 'approved');

CREATE INDEX refunds_status_idx ON refunds (status, requested_at);


-- ---------------------------------------------------------------------------
-- 6. policies (the text behind your policy pages)
-- ---------------------------------------------------------------------------

CREATE TABLE policies (
  id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  slug       TEXT        NOT NULL UNIQUE,
  title      TEXT        NOT NULL,
  body       TEXT        NOT NULL,
  position   INT         NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT policies_slug_format CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$')
);

CREATE TRIGGER policies_set_updated_at BEFORE UPDATE ON policies
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- ---------------------------------------------------------------------------
-- 7a. checkout_cart: cart -> order, in one transaction
-- ---------------------------------------------------------------------------
-- Returns the order number. Raises a plain-English error when something is
-- wrong, so your Go code can show err.Error() to the customer.

CREATE FUNCTION checkout_cart(
  p_session_token    TEXT,
  p_email            TEXT,
  p_shipping_address JSONB,
  p_coupon_code      TEXT DEFAULT NULL,
  p_idempotency_key  TEXT DEFAULT NULL
) RETURNS TEXT
LANGUAGE plpgsql AS $$
DECLARE
  v_cart     carts%ROWTYPE;
  v_coupon   coupons%ROWTYPE;
  v_bad      RECORD;
  v_order_id BIGINT;
  v_order_no TEXT;
  v_subtotal BIGINT;
  v_discount BIGINT := 0;
  v_shipping BIGINT;
  v_tax      BIGINT;
  v_count    INT;
BEGIN
  -- A double-clicked button sends the same key twice: return the first order.
  IF p_idempotency_key IS NOT NULL THEN
    SELECT order_number INTO v_order_no FROM orders WHERE idempotency_key = p_idempotency_key;
    IF FOUND THEN RETURN v_order_no; END IF;
  END IF;

  SELECT * INTO v_cart FROM carts WHERE session_token = p_session_token FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'cart not found'; END IF;

  IF NOT EXISTS (SELECT 1 FROM cart_items WHERE cart_id = v_cart.id) THEN
    RAISE EXCEPTION 'your cart is empty';
  END IF;

  -- Lock the variants being bought (in id order, so two checkouts can never
  -- deadlock each other). Nobody else can take this stock until we commit.
  PERFORM 1
  FROM product_variants v JOIN cart_items ci ON ci.variant_id = v.id
  WHERE ci.cart_id = v_cart.id
  ORDER BY v.id
  FOR UPDATE OF v;

  SELECT v.sku, v.stock, ci.quantity INTO v_bad
  FROM cart_items ci
  JOIN product_variants v ON v.id = ci.variant_id
  JOIN products p         ON p.id = v.product_id
  WHERE ci.cart_id = v_cart.id
    AND (NOT v.is_active OR NOT p.is_active OR v.stock < ci.quantity)
  LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'item % is unavailable or low on stock (in stock: %, in cart: %)',
      v_bad.sku, v_bad.stock, v_bad.quantity;
  END IF;

  SELECT sum(v.price_cents * ci.quantity) INTO v_subtotal
  FROM cart_items ci JOIN product_variants v ON v.id = ci.variant_id
  WHERE ci.cart_id = v_cart.id;

  -- Coupon ---------------------------------------------------------------
  IF p_coupon_code IS NOT NULL AND btrim(p_coupon_code) <> '' THEN
    IF v_cart.user_id IS NULL THEN
      RAISE EXCEPTION 'please log in to use a coupon';
    END IF;

    SELECT * INTO v_coupon FROM coupons
    WHERE code = upper(btrim(p_coupon_code)) FOR UPDATE;  -- lock: two people cannot grab the last use

    IF NOT FOUND OR NOT v_coupon.is_active THEN
      RAISE EXCEPTION 'this coupon code is not valid';
    END IF;
    IF now() < v_coupon.starts_at THEN
      RAISE EXCEPTION 'this coupon is not active yet';
    END IF;
    IF v_coupon.expires_at IS NOT NULL AND now() > v_coupon.expires_at THEN
      RAISE EXCEPTION 'this coupon has expired';
    END IF;
    IF v_subtotal < v_coupon.min_subtotal_cents THEN
      RAISE EXCEPTION 'this coupon needs a subtotal of at least % (yours is %)',
        to_char(v_coupon.min_subtotal_cents / 100.0, 'FM999,990.00'),
        to_char(v_subtotal / 100.0, 'FM999,990.00');
    END IF;

    SELECT count(*) INTO v_count FROM coupon_redemptions
    WHERE coupon_id = v_coupon.id AND released_at IS NULL;
    IF v_coupon.usage_limit IS NOT NULL AND v_count >= v_coupon.usage_limit THEN
      RAISE EXCEPTION 'this coupon has been fully used';
    END IF;

    SELECT count(*) INTO v_count FROM coupon_redemptions
    WHERE coupon_id = v_coupon.id AND user_id = v_cart.user_id AND released_at IS NULL;
    IF v_count >= v_coupon.per_user_limit THEN
      RAISE EXCEPTION 'you have already used this coupon';
    END IF;

    IF v_coupon.discount_type = 'percent' THEN
      v_discount := v_subtotal * v_coupon.discount_value / 100;
      IF v_coupon.max_discount_cents IS NOT NULL THEN
        v_discount := LEAST(v_discount, v_coupon.max_discount_cents);
      END IF;
    ELSE
      v_discount := v_coupon.discount_value;
    END IF;
    v_discount := LEAST(v_discount, v_subtotal);   -- never more than the order
  END IF;

  -- Shipping and tax -----------------------------------------------------
  v_shipping := CASE WHEN v_subtotal - v_discount >= setting_int('free_shipping_over_cents')
                     THEN 0 ELSE setting_int('shipping_flat_cents') END;
  v_tax := round((v_subtotal - v_discount) * setting_int('tax_rate_percent') / 100.0)::BIGINT;

  -- The order, its receipt lines, the stock, the coupon use ---------------
  INSERT INTO orders (user_id, email, status, subtotal_cents, shipping_cents, tax_cents,
                      discount_cents, shipping_address, idempotency_key, coupon_id, coupon_code)
  VALUES (v_cart.user_id, lower(btrim(p_email)), 'pending', v_subtotal, v_shipping, v_tax,
          v_discount, p_shipping_address, p_idempotency_key, v_coupon.id, v_coupon.code)
  RETURNING id, order_number INTO v_order_id, v_order_no;

  INSERT INTO order_items (order_id, variant_id, product_name, variant_name, sku,
                           unit_price_cents, quantity)
  SELECT v_order_id, v.id, p.name, v.name, v.sku, v.price_cents, ci.quantity
  FROM cart_items ci
  JOIN product_variants v ON v.id = ci.variant_id
  JOIN products p         ON p.id = v.product_id
  WHERE ci.cart_id = v_cart.id
  ORDER BY ci.id;

  UPDATE product_variants v
  SET stock = v.stock - ci.quantity
  FROM cart_items ci
  WHERE ci.cart_id = v_cart.id AND ci.variant_id = v.id;

  IF v_coupon.id IS NOT NULL THEN
    INSERT INTO coupon_redemptions (coupon_id, user_id, order_id, discount_cents)
    VALUES (v_coupon.id, v_cart.user_id, v_order_id, v_discount);
  END IF;

  DELETE FROM cart_items WHERE cart_id = v_cart.id;

  RETURN v_order_no;
END;
$$;


-- ---------------------------------------------------------------------------
-- 7b. cancel_order
-- ---------------------------------------------------------------------------
-- p_user_id = the logged-in customer (they can only cancel their own order).
-- Pass NULL when an admin cancels.

CREATE FUNCTION cancel_order(p_order_number TEXT, p_user_id BIGINT, p_reason TEXT DEFAULT '')
RETURNS VOID
LANGUAGE plpgsql AS $$
DECLARE
  o orders%ROWTYPE;
BEGIN
  SELECT * INTO o FROM orders WHERE order_number = p_order_number FOR UPDATE;
  IF NOT FOUND OR (p_user_id IS NOT NULL AND o.user_id IS DISTINCT FROM p_user_id) THEN
    RAISE EXCEPTION 'order not found';
  END IF;

  IF o.status NOT IN ('pending', 'paid', 'fulfilled') THEN
    RAISE EXCEPTION 'order % cannot be cancelled because it is %', o.order_number, o.status;
  END IF;

  -- Put the stock back.
  UPDATE product_variants v
  SET stock = v.stock + s.qty
  FROM (SELECT variant_id, sum(quantity) AS qty
        FROM order_items
        WHERE order_id = o.id AND variant_id IS NOT NULL
        GROUP BY variant_id) s
  WHERE v.id = s.variant_id;

  -- Give the coupon use back.
  UPDATE coupon_redemptions SET released_at = now()
  WHERE order_id = o.id AND released_at IS NULL;

  -- Money was already taken? Open an approved refund for the full amount.
  IF o.status IN ('paid', 'fulfilled') THEN
    INSERT INTO refunds (order_id, amount_cents, reason, status)
    VALUES (o.id, o.total_cents, 'Order cancelled: ' || COALESCE(NULLIF(p_reason, ''), 'no reason given'), 'approved');
  END IF;

  UPDATE orders SET status = 'cancelled', cancel_reason = COALESCE(p_reason, '')
  WHERE id = o.id;
END;
$$;


-- ---------------------------------------------------------------------------
-- 7c. request_refund and resolve_refund
-- ---------------------------------------------------------------------------

CREATE FUNCTION request_refund(p_order_number TEXT, p_user_id BIGINT, p_reason TEXT DEFAULT '')
RETURNS BIGINT
LANGUAGE plpgsql AS $$
DECLARE
  o orders%ROWTYPE;
  v_id BIGINT;
BEGIN
  SELECT * INTO o FROM orders WHERE order_number = p_order_number FOR UPDATE;
  IF NOT FOUND OR (p_user_id IS NOT NULL AND o.user_id IS DISTINCT FROM p_user_id) THEN
    RAISE EXCEPTION 'order not found';
  END IF;

  IF o.status <> 'delivered' THEN
    RAISE EXCEPTION 'only delivered orders can be refunded (this one is %)', o.status;
  END IF;

  IF now() > o.delivered_at + make_interval(days => setting_int('return_window_days')::INT) THEN
    RAISE EXCEPTION 'the % day return window for this order has closed', setting_int('return_window_days');
  END IF;

  IF EXISTS (SELECT 1 FROM refunds WHERE order_id = o.id AND status IN ('requested', 'approved')) THEN
    RAISE EXCEPTION 'a refund for this order is already in progress';
  END IF;

  INSERT INTO refunds (order_id, amount_cents, reason)
  VALUES (o.id, o.total_cents, COALESCE(p_reason, ''))
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- p_action: 'approve' | 'reject' | 'complete'   (the admin's three buttons)
CREATE FUNCTION resolve_refund(p_refund_id BIGINT, p_action TEXT)
RETURNS VOID
LANGUAGE plpgsql AS $$
DECLARE
  r refunds%ROWTYPE;
BEGIN
  SELECT * INTO r FROM refunds WHERE id = p_refund_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'refund not found'; END IF;

  IF p_action = 'approve' AND r.status = 'requested' THEN
    UPDATE refunds SET status = 'approved' WHERE id = r.id;

  ELSIF p_action = 'reject' AND r.status = 'requested' THEN
    UPDATE refunds SET status = 'rejected', resolved_at = now() WHERE id = r.id;

  ELSIF p_action = 'complete' AND r.status = 'approved' THEN
    UPDATE refunds SET status = 'refunded', resolved_at = now() WHERE id = r.id;
    -- A delivered order becomes 'refunded'. A cancelled order stays 'cancelled'.
    UPDATE orders SET status = 'refunded' WHERE id = r.order_id AND status = 'delivered';

  ELSE
    RAISE EXCEPTION 'cannot % a refund that is %', p_action, r.status;
  END IF;
END;
$$;


-- ---------------------------------------------------------------------------
-- Starter data: coupons and policies
-- ---------------------------------------------------------------------------

INSERT INTO coupons (code, description, discount_type, discount_value,
                     max_discount_cents, min_subtotal_cents, usage_limit, per_user_limit,
                     starts_at, expires_at)
VALUES
  ('WELCOME10', '10% off, up to 5.00',        'percent', 10,  500,    0, NULL, 1, now(), now() + interval '1 year'),
  ('SAVE5',     '5.00 off orders over 30.00', 'fixed',   500, NULL, 3000,   50, 1, now(), now() + interval '90 days'),
  ('FLASH50',   '50% off, 10 uses only',      'percent', 50, 2500,    0,   10, 1, now(), now() + interval '7 days'),
  -- Expired on purpose, so you can watch checkout reject it.
  ('OLD2020',   'Expired coupon, for testing', 'percent', 20, NULL,   0, NULL, 1,
               now() - interval '1 year', now() - interval '1 day');

INSERT INTO policies (slug, title, position, body) VALUES
('shipping', 'Shipping Policy', 1, $$
We ship every order within 1-2 working days of payment.

- Delivery usually takes 3-7 working days.
- Shipping costs 5.00 per order. It is free when your order, after any discount, reaches 100.00.
- You will get an email when your order ships.
- Please check your address at checkout. We cannot change it once the parcel has shipped.
$$),

('cancellation', 'Cancellation Policy', 2, $$
You can cancel an order yourself any time before it ships.

- Open "My orders" and press Cancel on the order.
- Once an order is marked Shipped it can no longer be cancelled. After it arrives you may return it instead (see the Refund Policy).
- If you already paid, we refund the full amount, including shipping and tax, to your original payment method.
- Any coupon you used on a cancelled order is returned to you and can be used again.
$$),

('refund', 'Refund and Return Policy', 3, $$
You can ask for a refund within 7 days of delivery.

- Open the delivered order and press Request refund. Tell us what went wrong.
- Items should be unused and in their original packaging. Opened coffee can only be refunded if it arrived damaged or was not what you ordered.
- We review every request. You will see the status change from Requested to Approved (or Rejected).
- Approved refunds are sent to your original payment method within 5-7 working days.
- Refunds cover the full amount you paid for the order.
- Refund requests made after the 7 day window cannot be accepted.
$$),

('coupons', 'Coupon Terms', 4, $$
- Each coupon code has its own rules: a minimum order, an expiry date and a limit on how many times it can be used.
- One coupon can be used per order. Coupons cannot be combined.
- A coupon cannot reduce your item total below zero.
- Coupons have no cash value.
- Coupons can only be used when you are logged in.
$$),

('privacy', 'Privacy Policy', 5, $$
We collect only what we need to process your order: your name, email, shipping address and order history.

- We never sell your personal data.
- We use your email only for order updates and account messages.
- You can ask us to delete your account. Order records are kept for accounting, but your personal details on them are removed.
$$);

COMMIT;
