-- ShopFlow seed data, expanded catalog
-- Apply AFTER schema.sql:
--   psql shopflow -f db/seed.sql
--
-- No hard-coded IDs: references are resolved by slug, SKU, or email.
-- This seed creates 30 products across coffee, equipment, grinders, and supplies.

BEGIN;

-- ---------------------------------------------------------------------------
-- categories
-- ---------------------------------------------------------------------------

INSERT INTO categories (slug, name, position) VALUES
  ('coffee',    'Coffee',    1),
  ('equipment', 'Equipment', 2),
  ('supplies',  'Supplies',  3);

-- A nested category, to demonstrate the self-reference.
INSERT INTO categories (slug, name, position, parent_id)
VALUES (
  'grinders', 'Grinders', 1,
  (SELECT id FROM categories WHERE slug = 'equipment')
);

-- ---------------------------------------------------------------------------
-- products
-- ---------------------------------------------------------------------------

INSERT INTO products (slug, name, description, category_id) VALUES
  -- Coffee
  ('ethiopian-yirgacheffe', 'Ethiopian Yirgacheffe',
   'Bright, floral single-origin beans. Washed, light roast.',
   (SELECT id FROM categories WHERE slug = 'coffee')),

  ('colombian-supremo', 'Colombian Supremo',
   'Balanced and nutty, the everyday cup. Medium roast.',
   (SELECT id FROM categories WHERE slug = 'coffee')),

  ('decaf-sumatra', 'Decaf Sumatra',
   'Full-bodied and earthy, no caffeine. Swiss water process.',
   (SELECT id FROM categories WHERE slug = 'coffee')),

  ('kenya-aa', 'Kenya AA',
   'Juicy blackcurrant and citrus notes with a bright, clean finish.',
   (SELECT id FROM categories WHERE slug = 'coffee')),

  ('brazil-santos', 'Brazil Santos',
   'Smooth, low-acidity coffee with chocolate and roasted-nut notes.',
   (SELECT id FROM categories WHERE slug = 'coffee')),

  ('guatemala-antigua', 'Guatemala Antigua',
   'Medium-roast single origin with cocoa, caramel, and orange notes.',
   (SELECT id FROM categories WHERE slug = 'coffee')),

  ('costa-rica-tarrazu', 'Costa Rica Tarrazú',
   'Clean, balanced coffee with honey sweetness and a crisp finish.',
   (SELECT id FROM categories WHERE slug = 'coffee')),

  ('house-espresso-blend', 'House Espresso Blend',
   'A balanced espresso blend developed for milk drinks and espresso.',
   (SELECT id FROM categories WHERE slug = 'coffee')),

  ('rwanda-bourbon', 'Rwanda Bourbon',
   'A sweet, delicate coffee with stone-fruit and floral notes.',
   (SELECT id FROM categories WHERE slug = 'coffee')),

  ('sumatra-mandheling', 'Sumatra Mandheling',
   'Deep-bodied Indonesian coffee with earthy and spice notes.',
   (SELECT id FROM categories WHERE slug = 'coffee')),

  -- Equipment
  ('gooseneck-kettle', 'Gooseneck Kettle',
   '1L stainless steel kettle for precise pour control.',
   (SELECT id FROM categories WHERE slug = 'equipment')),

  ('ceramic-dripper-v60', 'Ceramic Dripper V60',
   'Size 02 ceramic pour-over dripper for one to four cups.',
   (SELECT id FROM categories WHERE slug = 'equipment')),

  ('french-press-600', 'French Press 600ml',
   'Glass and stainless-steel French press for full-bodied coffee.',
   (SELECT id FROM categories WHERE slug = 'equipment')),

  ('aeropress-coffee-maker', 'AeroPress Coffee Maker',
   'Compact manual coffee maker for smooth, low-bitterness brews.',
   (SELECT id FROM categories WHERE slug = 'equipment')),

  ('stovetop-moka-pot', 'Stovetop Moka Pot',
   'Six-cup aluminium stovetop brewer for rich, concentrated coffee.',
   (SELECT id FROM categories WHERE slug = 'equipment')),

  ('espresso-machine', 'Home Espresso Machine',
   'Compact espresso machine for home brewing.',
   (SELECT id FROM categories WHERE slug = 'equipment')),

  ('digital-coffee-scale', 'Digital Coffee Scale',
   'Precision scale with timer for repeatable coffee brewing.',
   (SELECT id FROM categories WHERE slug = 'equipment')),

  -- Grinders
  ('burr-grinder', 'Burr Grinder',
   '40mm conical burrs with 30 grind settings.',
   (SELECT id FROM categories WHERE slug = 'grinders')),

  ('hand-coffee-grinder', 'Manual Coffee Grinder',
   'Portable hand grinder with adjustable ceramic burr settings.',
   (SELECT id FROM categories WHERE slug = 'grinders')),

  ('electric-burr-grinder', 'Electric Burr Grinder',
   'Countertop burr grinder with multiple grind-size settings.',
   (SELECT id FROM categories WHERE slug = 'grinders')),

  -- Supplies and accessories
  ('paper-filters-100', 'Paper Filters (100)',
   'Natural unbleached paper filters, size 02.',
   (SELECT id FROM categories WHERE slug = 'supplies')),

  ('shop-mug', 'Shop Mug',
   '350ml stoneware mug, dishwasher safe.',
   (SELECT id FROM categories WHERE slug = 'supplies')),

  ('reusable-metal-filter', 'Reusable Metal Filter',
   'Reusable stainless-steel filter for compatible pour-over brewers.',
   (SELECT id FROM categories WHERE slug = 'supplies')),

  ('coffee-server-600', 'Glass Coffee Server',
   '600ml heat-resistant glass server with measurement markings.',
   (SELECT id FROM categories WHERE slug = 'supplies')),

  ('espresso-tamper', 'Espresso Tamper',
   'Flat-base stainless-steel tamper for consistent puck preparation.',
   (SELECT id FROM categories WHERE slug = 'supplies')),

  ('milk-frothing-pitcher', 'Milk Frothing Pitcher',
   '600ml stainless-steel pitcher for steaming and pouring milk.',
   (SELECT id FROM categories WHERE slug = 'supplies')),

  ('coffee-filter-papers-200', 'Cone Filter Papers (200)',
   'Pack of 200 cone-shaped paper filters for pour-over brewing.',
   (SELECT id FROM categories WHERE slug = 'supplies')),

  ('coffee-cleaning-tablets', 'Coffee Machine Cleaning Tablets',
   'Cleaning tablets for routine espresso machine maintenance.',
   (SELECT id FROM categories WHERE slug = 'supplies')),

  ('coffee-canister', 'Airtight Coffee Canister',
   'Airtight storage canister designed to help keep coffee fresh.',
   (SELECT id FROM categories WHERE slug = 'supplies')),

  ('cupping-spoon-set', 'Coffee Cupping Spoon Set',
   'Stainless-steel spoons for coffee tasting and brewing.',
   (SELECT id FROM categories WHERE slug = 'supplies'));

-- ---------------------------------------------------------------------------
-- variants
-- ---------------------------------------------------------------------------
-- Coffee products have multiple bag sizes. Equipment and supplies have
-- practical variants where relevant; all use the same table and query path.

INSERT INTO product_variants
  (product_id, sku, name, price_cents, stock, weight_grams, position)
VALUES
  -- Ethiopian Yirgacheffe
  ((SELECT id FROM products WHERE slug = 'ethiopian-yirgacheffe'), 'COF-YIR-250', '250g', 1850, 42, 250, 1),
  ((SELECT id FROM products WHERE slug = 'ethiopian-yirgacheffe'), 'COF-YIR-1KG', '1kg', 6200, 8, 1000, 2),

  -- Colombian Supremo
  ((SELECT id FROM products WHERE slug = 'colombian-supremo'), 'COF-COL-250', '250g', 1450, 60, 250, 1),
  ((SELECT id FROM products WHERE slug = 'colombian-supremo'), 'COF-COL-1KG', '1kg', 4900, 15, 1000, 2),

  -- Decaf Sumatra: deliberately sold out to exercise stock filtering.
  ((SELECT id FROM products WHERE slug = 'decaf-sumatra'), 'COF-SUM-250', '250g', 1650, 0, 250, 1),
  ((SELECT id FROM products WHERE slug = 'decaf-sumatra'), 'COF-SUM-1KG', '1kg', 5600, 4, 1000, 2),

  -- Additional coffee
  ((SELECT id FROM products WHERE slug = 'kenya-aa'), 'COF-KEN-250', '250g', 2100, 18, 250, 1),
  ((SELECT id FROM products WHERE slug = 'kenya-aa'), 'COF-KEN-1KG', '1kg', 7200, 6, 1000, 2),

  ((SELECT id FROM products WHERE slug = 'brazil-santos'), 'COF-BRA-250', '250g', 1350, 75, 250, 1),
  ((SELECT id FROM products WHERE slug = 'brazil-santos'), 'COF-BRA-1KG', '1kg', 4500, 20, 1000, 2),

  ((SELECT id FROM products WHERE slug = 'guatemala-antigua'), 'COF-GUA-250', '250g', 1750, 24, 250, 1),
  ((SELECT id FROM products WHERE slug = 'guatemala-antigua'), 'COF-GUA-1KG', '1kg', 6100, 9, 1000, 2),

  ((SELECT id FROM products WHERE slug = 'costa-rica-tarrazu'), 'COF-CRC-250', '250g', 1950, 14, 250, 1),
  ((SELECT id FROM products WHERE slug = 'costa-rica-tarrazu'), 'COF-CRC-1KG', '1kg', 6800, 5, 1000, 2),

  ((SELECT id FROM products WHERE slug = 'house-espresso-blend'), 'COF-HSE-250', '250g', 1550, 50, 250, 1),
  ((SELECT id FROM products WHERE slug = 'house-espresso-blend'), 'COF-HSE-1KG', '1kg', 5200, 16, 1000, 2),

  ((SELECT id FROM products WHERE slug = 'rwanda-bourbon'), 'COF-RWA-250', '250g', 2050, 12, 250, 1),
  ((SELECT id FROM products WHERE slug = 'rwanda-bourbon'), 'COF-RWA-1KG', '1kg', 7000, 4, 1000, 2),

  ((SELECT id FROM products WHERE slug = 'sumatra-mandheling'), 'COF-MAN-250', '250g', 1600, 28, 250, 1),
  ((SELECT id FROM products WHERE slug = 'sumatra-mandheling'), 'COF-MAN-1KG', '1kg', 5500, 7, 1000, 2),

  -- Equipment
  ((SELECT id FROM products WHERE slug = 'gooseneck-kettle'), 'EQP-KET-1L', '1L', 5900, 12, 900, 1),
  ((SELECT id FROM products WHERE slug = 'ceramic-dripper-v60'), 'EQP-V60-02', 'Size 02', 2400, 25, 300, 1),
  ((SELECT id FROM products WHERE slug = 'french-press-600'), 'EQP-FRP-600', '600ml', 3200, 19, 500, 1),
  ((SELECT id FROM products WHERE slug = 'aeropress-coffee-maker'), 'EQP-AER-STD', 'Standard', 4800, 11, 250, 1),
  ((SELECT id FROM products WHERE slug = 'stovetop-moka-pot'), 'EQP-MOK-6C', '6 cup', 3900, 17, 450, 1),
  ((SELECT id FROM products WHERE slug = 'espresso-machine'), 'EQP-ESP-HOME', 'Home', 24900, 5, 4200, 1),
  ((SELECT id FROM products WHERE slug = 'digital-coffee-scale'), 'EQP-SCL-DIG', 'Default', 3500, 22, 350, 1),

  -- Grinders
  ((SELECT id FROM products WHERE slug = 'burr-grinder'), 'EQP-GRN-40', '40mm burr', 12900, 7, 1800, 1),
  ((SELECT id FROM products WHERE slug = 'hand-coffee-grinder'), 'GRN-HND-01', 'Manual', 4500, 16, 500, 1),
  ((SELECT id FROM products WHERE slug = 'electric-burr-grinder'), 'GRN-ELC-01', 'Electric', 15900, 3, 2200, 1),

  -- Supplies and accessories
  ((SELECT id FROM products WHERE slug = 'paper-filters-100'), 'SUP-FIL-100', '100 filters', 800, 200, 120, 1),
  ((SELECT id FROM products WHERE slug = 'shop-mug'), 'SUP-MUG-350', '350ml', 1900, 33, 400, 1),
  ((SELECT id FROM products WHERE slug = 'reusable-metal-filter'), 'SUP-MTF-01', 'Default', 1450, 26, 80, 1),
  ((SELECT id FROM products WHERE slug = 'coffee-server-600'), 'SUP-SRV-600', '600ml', 2600, 13, 420, 1),
  ((SELECT id FROM products WHERE slug = 'espresso-tamper'), 'SUP-TMP-58', '58mm', 2900, 18, 350, 1),
  ((SELECT id FROM products WHERE slug = 'milk-frothing-pitcher'), 'SUP-PIT-600', '600ml', 2200, 21, 300, 1),
  ((SELECT id FROM products WHERE slug = 'coffee-filter-papers-200'), 'SUP-FIL-200', '200 filters', 1350, 85, 220, 1),
  ((SELECT id FROM products WHERE slug = 'coffee-cleaning-tablets'), 'SUP-CLN-100', '100g pack', 1700, 2, 120, 1),
  ((SELECT id FROM products WHERE slug = 'coffee-canister'), 'SUP-CAN-500', '500g', 2400, 31, 380, 1),
  ((SELECT id FROM products WHERE slug = 'cupping-spoon-set'), 'SUP-CUP-SET', 'Set of 2', 1600, 14, 180, 1);

-- ---------------------------------------------------------------------------
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
