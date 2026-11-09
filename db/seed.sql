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
