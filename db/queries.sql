-- ShopFlow: the queries the Go code will run in Stage 3.
-- Read them here, in psql, before they are buried inside Go string literals.
-- Run one at a time:  psql shopflow  then paste.

-- ---------------------------------------------------------------------------
-- 1. The storefront listing
-- ---------------------------------------------------------------------------
-- One row per product, with the price range and total stock rolled up from its
-- variants. This is the query behind the grid you already built in Stage 1.

SELECT
  p.id,
  p.slug,
  p.name,
  c.name                    AS category,
  min(v.price_cents)        AS from_price_cents,
  max(v.price_cents)        AS to_price_cents,
  sum(v.stock)              AS total_stock,
  count(v.id)               AS variant_count,
  min(i.url)                AS image_url
FROM products p
LEFT JOIN categories c      ON c.id = p.category_id
-- LEFT JOIN, not JOIN: a product with no variants yet should still appear in
-- an admin list rather than silently vanishing. Swap to JOIN for the public
-- storefront, where an unpriceable product has no business being shown.
LEFT JOIN product_variants v ON v.product_id = p.id AND v.is_active
LEFT JOIN product_images i   ON i.product_id = p.id
WHERE p.is_active
GROUP BY p.id, p.slug, p.name, c.name
ORDER BY p.name;


-- ---------------------------------------------------------------------------
-- 2. One product page, with every variant
-- ---------------------------------------------------------------------------

SELECT
  p.name, p.description,
  v.id AS variant_id, v.sku, v.name AS variant, v.price_cents, v.stock,
  (v.stock > 0) AS in_stock
FROM products p
JOIN product_variants v ON v.product_id = p.id
WHERE p.slug = 'colombian-supremo' AND p.is_active AND v.is_active
ORDER BY v.position;


-- ---------------------------------------------------------------------------
-- 3. A cart, priced live
-- ---------------------------------------------------------------------------
-- The cart stores only variant_id and quantity. The money is computed from the
-- catalog at read time, on purpose, so a price change is reflected before the
-- customer commits to it. Compare with query 4.

SELECT
  p.name, v.name AS variant, v.price_cents, ci.quantity,
  v.price_cents * ci.quantity AS line_cents,
  (v.stock >= ci.quantity)    AS still_available
FROM cart_items ci
JOIN product_variants v ON v.id = ci.variant_id
JOIN products p         ON p.id = v.product_id
JOIN carts ct           ON ct.id = ci.cart_id
WHERE ct.session_token = 'demo-session-token'
ORDER BY ci.added_at;

-- The cart's subtotal.
SELECT sum(v.price_cents * ci.quantity) AS subtotal_cents
FROM cart_items ci
JOIN product_variants v ON v.id = ci.variant_id
JOIN carts ct           ON ct.id = ci.cart_id
WHERE ct.session_token = 'demo-session-token';


-- ---------------------------------------------------------------------------
-- 4. An order, priced from the snapshot
-- ---------------------------------------------------------------------------
-- Notice what is NOT here: product_variants. This query cannot be affected by
-- anything that happens to the catalog, because it never touches it.

SELECT
  o.order_number, o.status, o.placed_at::date AS placed,
  oi.product_name, oi.variant_name, oi.sku,
  oi.unit_price_cents, oi.quantity, oi.line_total_cents
FROM orders o
JOIN order_items oi ON oi.order_id = o.id
WHERE o.order_number = 'SF-1001'
ORDER BY oi.id;

-- Proof that the stored totals agree with the lines. This should always be
-- true; if it ever is not, something wrote a total by hand.
SELECT
  o.order_number,
  o.subtotal_cents                AS stored_subtotal,
  sum(oi.line_total_cents)        AS computed_subtotal,
  o.subtotal_cents = sum(oi.line_total_cents) AS agrees
FROM orders o
JOIN order_items oi ON oi.order_id = o.id
GROUP BY o.id, o.order_number, o.subtotal_cents;


-- ---------------------------------------------------------------------------
-- 5. Order history for one customer
-- ---------------------------------------------------------------------------

SELECT
  o.order_number,
  o.placed_at::date AS placed,
  o.status,
  count(oi.id)      AS items,
  o.total_cents,
  -- Formatting money for humans, done in SQL for once so you can see the shape.
  to_char(o.total_cents / 100.0, 'FM999,999,990.00') AS total
FROM orders o
JOIN users u        ON u.id = o.user_id
LEFT JOIN order_items oi ON oi.order_id = o.id
WHERE u.email = 'tishad@example.com'
GROUP BY o.id
ORDER BY o.placed_at DESC;


-- ---------------------------------------------------------------------------
-- 6. Shop reports
-- ---------------------------------------------------------------------------

-- What is nearly out of stock?
SELECT p.name, v.sku, v.name AS variant, v.stock
FROM product_variants v
JOIN products p ON p.id = v.product_id
WHERE v.stock < 10 AND v.is_active
ORDER BY v.stock;

-- Best sellers, by units, from the snapshot rather than the catalog, so
-- discontinued products still count towards history.
SELECT oi.product_name, oi.sku,
       sum(oi.quantity)         AS units_sold,
       sum(oi.line_total_cents) AS revenue_cents
FROM order_items oi
JOIN orders o ON o.id = oi.order_id
WHERE o.status IN ('paid', 'fulfilled', 'shipped', 'delivered')
GROUP BY oi.product_name, oi.sku
ORDER BY units_sold DESC;

-- Revenue by day.
SELECT o.placed_at::date AS day,
       count(*)          AS orders,
       sum(o.total_cents) AS revenue_cents
FROM orders o
WHERE o.status <> 'cancelled'
GROUP BY day
ORDER BY day DESC;
