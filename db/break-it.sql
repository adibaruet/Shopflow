-- ShopFlow Stage 2: things that must be impossible.
--
-- Run it:  psql shopflow -f db/break-it.sql
--
-- Every statement below is supposed to FAIL. A wall of red ERROR lines is the
-- success condition. Read each message: the constraint name tells you exactly
-- which rule you hit, which is why the constraints in schema.sql are named
-- rather than left for Postgres to call check_constraint_7.
--
-- Nothing here is wrapped in a transaction, so nothing is left behind. The one
-- statement that succeeds is clearly marked at the end.

\set ON_ERROR_STOP off
\pset border 2

\echo ''
\echo '=== 1. A product that costs nothing ==='
INSERT INTO product_variants (product_id, sku, name, price_cents)
VALUES ((SELECT id FROM products LIMIT 1), 'TEST-FREE', 'Free', 0);

\echo ''
\echo '=== 2. Selling more than you have ==='
UPDATE product_variants SET stock = -1 WHERE sku = 'SUP-MUG-350';

\echo ''
\echo '=== 3. Two things with the same SKU ==='
INSERT INTO product_variants (product_id, sku, name, price_cents)
VALUES ((SELECT id FROM products LIMIT 1), 'COF-YIR-250', 'Impostor', 100);

\echo ''
\echo '=== 4. The same email in different capitals ==='
INSERT INTO users (email, password_hash) VALUES ('TISHAD@Example.COM', 'x');

\echo ''
\echo '=== 5. A status nobody defined ==='
UPDATE orders SET status = 'in_the_post' WHERE order_number = 'SF-1001';

\echo ''
\echo '=== 6. A discount larger than the order ==='
UPDATE orders SET discount_cents = 999999 WHERE order_number = 'SF-1001';

\echo ''
\echo '=== 7. Writing a total by hand ==='
UPDATE orders SET total_cents = 1 WHERE order_number = 'SF-1001';

\echo ''
\echo '=== 8. Deleting a customer who has bought something ==='
DELETE FROM users WHERE email = 'tishad@example.com';

\echo ''
\echo '=== 9. Zero of something in a cart ==='
UPDATE cart_items SET quantity = 0 WHERE id = (SELECT min(id) FROM cart_items);

\echo ''
\echo '=== 10. A second open cart for one logged-in customer ==='
INSERT INTO carts (user_id, session_token)
VALUES ((SELECT id FROM users WHERE email = 'tishad@example.com'), 'second-token');

\echo ''
\echo '=== 11. A slug that will not survive a URL ==='
INSERT INTO products (slug, name) VALUES ('Not A Slug!', 'Bad');

\echo ''
\echo '=== 12. Lowercase currency ==='
INSERT INTO product_variants (product_id, sku, name, price_cents, currency)
VALUES ((SELECT id FROM products LIMIT 1), 'TEST-CUR', 'Cur', 100, 'usd');

\echo ''
\echo '############################################################'
\echo '# Now the one that SUCCEEDS, and is the point of the stage. #'
\echo '############################################################'
\echo ''
\echo '--- The catalog price and the receipt, before ---'
SELECT v.sku, v.price_cents AS catalog_price FROM product_variants v WHERE v.sku = 'COF-YIR-250';
SELECT sku, unit_price_cents AS receipt_price, quantity, line_total_cents FROM order_items WHERE sku = 'COF-YIR-250';

\echo ''
\echo '--- Raise the shelf price to 21.00 ---'
UPDATE product_variants SET price_cents = 2100 WHERE sku = 'COF-YIR-250';

\echo ''
\echo '--- The catalog moved. The receipt did not. ---'
SELECT v.sku, v.price_cents AS catalog_price FROM product_variants v WHERE v.sku = 'COF-YIR-250';
SELECT sku, unit_price_cents AS receipt_price, quantity, line_total_cents FROM order_items WHERE sku = 'COF-YIR-250';
SELECT order_number, subtotal_cents, total_cents FROM orders;

\echo ''
\echo '--- Discontinue the product completely ---'
DELETE FROM products WHERE slug = 'ethiopian-yirgacheffe';

\echo ''
\echo '--- Variants are gone (ON DELETE CASCADE) ---'
SELECT count(*) AS yirgacheffe_variants_left FROM product_variants WHERE sku LIKE 'COF-YIR%';

\echo ''
\echo '--- The sale still happened. Only the pointer went NULL. ---'
SELECT variant_id, product_name, variant_name, sku, unit_price_cents, quantity, line_total_cents
FROM order_items ORDER BY id;
SELECT order_number, subtotal_cents, total_cents FROM orders;

\echo ''
\echo 'Put it back with:  psql shopflow -f db/schema.sql && psql shopflow -f db/seed.sql'
