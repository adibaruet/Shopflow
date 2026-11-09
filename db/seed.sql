-- ShopFlow seed data, Stage 2
-- Apply AFTER schema.sql:  psql shopflow -f db/seed.sql
--
-- Notice there is not a single hard-coded id in this file. Every reference is
-- looked up by slug or SKU. Ids are the database's business, not yours, and a
-- seed file full of "17" breaks the moment you reorder an INSERT.

BEGIN;

-- ---------------------------------------------------------------------------
-- categories
-- ---------------------------------------------------------------------------

INSERT INTO categories (slug, name, position) VALUES
  ('coffee',    'Coffee',    1),
  ('equipment', 'Equipment', 2),
  ('supplies',  'Supplies',  3);

-- A nested category, to show the self-reference doing its job.
INSERT INTO categories (slug, name, position, parent_id)
VALUES ('grinders', 'Grinders', 1,
        (SELECT id FROM categories WHERE slug = 'equipment'));


-- ---------------------------------------------------------------------------
-- products
-- ---------------------------------------------------------------------------

INSERT INTO products (slug, name, description, category_id) VALUES
  ('ethiopian-yirgacheffe', 'Ethiopian Yirgacheffe',
   'Bright, floral single-origin beans. Washed, light roast.',
   (SELECT id FROM categories WHERE slug = 'coffee')),

  ('colombian-supremo', 'Colombian Supremo',
   'Balanced and nutty, the everyday cup. Medium roast.',
   (SELECT id FROM categories WHERE slug = 'coffee')),

  ('decaf-sumatra', 'Decaf Sumatra',
   'Full-bodied and earthy, no caffeine. Swiss water process.',
   (SELECT id FROM categories WHERE slug = 'coffee')),

  ('gooseneck-kettle', 'Gooseneck Kettle',
   '1L stainless steel, precise pour control.',
   (SELECT id FROM categories WHERE slug = 'equipment')),

  ('burr-grinder', 'Burr Grinder',
   '40mm conical burrs, 30 grind settings.',
   (SELECT id FROM categories WHERE slug = 'grinders')),

  ('ceramic-dripper-v60', 'Ceramic Dripper V60',
   'Size 02, makes one to four cups.',
   (SELECT id FROM categories WHERE slug = 'equipment')),

  ('paper-filters-100', 'Paper Filters (100)',
   'Natural unbleached, size 02.',
   (SELECT id FROM categories WHERE slug = 'supplies')),

  ('shop-mug', 'Shop Mug',
   '350ml stoneware, dishwasher safe.',
   (SELECT id FROM categories WHERE slug = 'supplies'));


-- ---------------------------------------------------------------------------
-- variants
-- ---------------------------------------------------------------------------
-- The coffees have two sizes each. Everything else has one variant named
-- 'Default'. Same table, same queries, no special case anywhere in Go.

INSERT INTO product_variants (product_id, sku, name, price_cents, stock, weight_grams, position) VALUES
  ((SELECT id FROM products WHERE slug = 'ethiopian-yirgacheffe'), 'COF-YIR-250', '250g',  1850, 42,  250, 1),
  ((SELECT id FROM products WHERE slug = 'ethiopian-yirgacheffe'), 'COF-YIR-1KG', '1kg',   6200,  8, 1000, 2),

  ((SELECT id FROM products WHERE slug = 'colombian-supremo'),     'COF-COL-250', '250g',  1450, 60,  250, 1),
  ((SELECT id FROM products WHERE slug = 'colombian-supremo'),     'COF-COL-1KG', '1kg',   4900, 15, 1000, 2),

  -- Sold out, deliberately: the storefront has to handle stock = 0.
  ((SELECT id FROM products WHERE slug = 'decaf-sumatra'),         'COF-SUM-250', '250g',  1650,  0,  250, 1),

  ((SELECT id FROM products WHERE slug = 'gooseneck-kettle'),      'EQP-KET-1L',  'Default', 5900, 12, 900, 1),
  ((SELECT id FROM products WHERE slug = 'burr-grinder'),          'EQP-GRN-40',  'Default',12900,  7, 1800, 1),
  ((SELECT id FROM products WHERE slug = 'ceramic-dripper-v60'),   'EQP-V60-02',  'Default', 2400, 25, 300, 1),
  ((SELECT id FROM products WHERE slug = 'paper-filters-100'),     'SUP-FIL-100', 'Default',  800,200,  120, 1),
  ((SELECT id FROM products WHERE slug = 'shop-mug'),              'SUP-MUG-350', 'Default', 1900, 33, 400, 1);


-- ---------------------------------------------------------------------------
-- images (reusing the SVGs from Stage 1)
-- ---------------------------------------------------------------------------

INSERT INTO product_images (product_id, url, alt, position)
SELECT id, '/img/' || slug || '.svg', name, 1 FROM products;


-- ---------------------------------------------------------------------------
-- a customer
-- ---------------------------------------------------------------------------
-- The hash is a real bcrypt hash of the password "shopflow". Stage 5 replaces
-- this with a signup endpoint that generates its own.

INSERT INTO users (email, password_hash, full_name) VALUES
  ('tishad@example.com', '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'Tishad Ashef');

INSERT INTO addresses (user_id, label, recipient, line1, city, region, postal_code, country_code, phone)
VALUES ((SELECT id FROM users WHERE email = 'tishad@example.com'),
        'Home', 'Tishad Ashef', '12 Kazla Road', 'Rajshahi', 'Rajshahi', '6204', 'BD', '+880000000000');


-- ---------------------------------------------------------------------------
-- an open cart
-- ---------------------------------------------------------------------------

INSERT INTO carts (user_id, session_token)
VALUES ((SELECT id FROM users WHERE email = 'tishad@example.com'), 'demo-session-token');

INSERT INTO cart_items (cart_id, variant_id, quantity) VALUES
  ((SELECT id FROM carts WHERE session_token = 'demo-session-token'),
   (SELECT id FROM product_variants WHERE sku = 'COF-COL-1KG'), 1),
  ((SELECT id FROM carts WHERE session_token = 'demo-session-token'),
   (SELECT id FROM product_variants WHERE sku = 'SUP-FIL-100'), 2);


-- ---------------------------------------------------------------------------
-- one placed order, so there is history to protect
-- ---------------------------------------------------------------------------
-- 2 x Yirgacheffe 250g at 1850  = 3700
-- 1 x Ceramic Dripper V60       = 2400
--                      subtotal = 6100
--                      shipping =  500
--                       tax (8%) =  488
--                   total_cents  = 7088   <- computed by Postgres, not by this file

INSERT INTO orders (user_id, email, status, subtotal_cents, shipping_cents, tax_cents, shipping_address)
VALUES (
  (SELECT id FROM users WHERE email = 'tishad@example.com'),
  'tishad@example.com',
  'paid',
  6100, 500, 488,
  '{"recipient":"Tishad Ashef","line1":"12 Kazla Road","city":"Rajshahi",
    "region":"Rajshahi","postal_code":"6204","country_code":"BD"}'::jsonb
);

-- The snapshot. Every value here is copied out of the catalog AS IT IS NOW,
-- and will not change when the catalog does.
INSERT INTO order_items (order_id, variant_id, product_name, variant_name, sku, unit_price_cents, quantity)
SELECT
  (SELECT id FROM orders ORDER BY id DESC LIMIT 1),
  v.id, p.name, v.name, v.sku, v.price_cents, 2
FROM product_variants v JOIN products p ON p.id = v.product_id
WHERE v.sku = 'COF-YIR-250';

INSERT INTO order_items (order_id, variant_id, product_name, variant_name, sku, unit_price_cents, quantity)
SELECT
  (SELECT id FROM orders ORDER BY id DESC LIMIT 1),
  v.id, p.name, v.name, v.sku, v.price_cents, 1
FROM product_variants v JOIN products p ON p.id = v.product_id
WHERE v.sku = 'EQP-V60-02';

COMMIT;
