-- images
-- ---------------------------------------------------------------------------
-- The original eight products keep their individual Stage 1 SVGs.
-- New products temporarily reuse a category-specific image so no product
-- card points to a missing local asset. Add individual SVGs later if desired.

INSERT INTO product_images (product_id, url, alt, position)
SELECT
  p.id,
  CASE
    WHEN p.slug IN (
      'ethiopian-yirgacheffe', 'colombian-supremo', 'decaf-sumatra',
      'gooseneck-kettle', 'burr-grinder', 'ceramic-dripper-v60',
      'paper-filters-100', 'shop-mug'
    ) THEN '/img/' || p.slug || '.svg'
    WHEN c.slug = 'coffee' THEN '/img/ethiopian-yirgacheffe.svg'
    WHEN c.slug = 'grinders' THEN '/img/burr-grinder.svg'
    WHEN c.slug = 'equipment' THEN '/img/gooseneck-kettle.svg'
    ELSE '/img/shop-mug.svg'
  END,
  p.name,
  1
FROM products p
JOIN categories c ON c.id = p.category_id;

-- ---------------------------------------------------------------------------
-- a customer
-- ---------------------------------------------------------------------------
-- Demo credentials are for local/demo use only. Replace with a newly
-- generated bcrypt hash before using any real customer account.

INSERT INTO users (email, password_hash, full_name) VALUES
  ('tishad@example.com', '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'Tishad Ashef');

INSERT INTO addresses
  (user_id, label, recipient, line1, city, region, postal_code, country_code, phone)
VALUES (
  (SELECT id FROM users WHERE email = 'tishad@example.com'),
  'Home', 'Tishad Ashef', '12 Kazla Road', 'Rajshahi', 'Rajshahi',
  '6204', 'BD', '+880000000000'
);

-- ---------------------------------------------------------------------------
-- an open cart
-- ---------------------------------------------------------------------------

INSERT INTO carts (user_id, session_token)
VALUES (
  (SELECT id FROM users WHERE email = 'tishad@example.com'),
  'demo-session-token'
);

INSERT INTO cart_items (cart_id, variant_id, quantity) VALUES
  (
    (SELECT id FROM carts WHERE session_token = 'demo-session-token'),
    (SELECT id FROM product_variants WHERE sku = 'COF-COL-1KG'), 1
  ),
  (
    (SELECT id FROM carts WHERE session_token = 'demo-session-token'),
    (SELECT id FROM product_variants WHERE sku = 'SUP-FIL-100'), 2
  );

-- ---------------------------------------------------------------------------
-- one placed order, so there is history to protect
-- ---------------------------------------------------------------------------
-- 2 x Yirgacheffe 250g at 1850 = 3700
-- 1 x Ceramic Dripper V60       = 2400
-- subtotal                     = 6100
-- shipping                     =  500
-- tax (8%)                     =  488
-- total_cents                  = 7088 (computed by PostgreSQL)

INSERT INTO orders
  (user_id, email, status, subtotal_cents, shipping_cents, tax_cents, shipping_address)
VALUES (
  (SELECT id FROM users WHERE email = 'tishad@example.com'),
  'tishad@example.com',
  'paid',
  6100, 500, 488,
  '{"recipient":"Tishad Ashef","line1":"12 Kazla Road","city":"Rajshahi",
    "region":"Rajshahi","postal_code":"6204","country_code":"BD"}'::jsonb
);

-- Snapshot catalog values at purchase time.
INSERT INTO order_items
  (order_id, variant_id, product_name, variant_name, sku, unit_price_cents, quantity)
SELECT
  (SELECT id FROM orders ORDER BY id DESC LIMIT 1),
  v.id, p.name, v.name, v.sku, v.price_cents, 2
FROM product_variants v
JOIN products p ON p.id = v.product_id
WHERE v.sku = 'COF-YIR-250';

INSERT INTO order_items
  (order_id, variant_id, product_name, variant_name, sku, unit_price_cents, quantity)
SELECT
  (SELECT id FROM orders ORDER BY id DESC LIMIT 1),
  v.id, p.name, v.name, v.sku, v.price_cents, 1
FROM product_variants v
JOIN products p ON p.id = v.product_id
WHERE v.sku = 'EQP-V60-02';

COMMIT;
