-- Seed data for customers, orders, and order_items.
-- Run after schema.sql: psql "$DATABASE_URL" -f schema.sql -f seed.sql

-- Customers
INSERT INTO customers (id, name, email, signup_date, status, plan) VALUES
  (1,  'Acme Corp',          'billing@acme.com',        '2023-01-15', 'active',  'enterprise'),
  (2,  'Bright Ideas LLC',   'hello@brightideas.io',    '2023-03-22', 'active',  'pro'),
  (3,  'Solo Dev',           'me@solodev.com',           '2023-06-01', 'trial',   'free'),
  (4,  'Departed Ltd',       'info@departed.co',         '2022-11-10', 'churned', 'pro'),
  (5,  'Startup House',      'ops@starthouse.ai',        '2024-02-28', 'active',  'pro'),
  (6,  'Big Fish Inc',       'accounts@bigfish.com',     '2021-08-05', 'active',  'enterprise'),
  (7,  'Tiny Shop',          'owner@tinyshop.net',       '2024-05-10', 'trial',   'free'),
  (8,  'Old Guard Co',       'contact@oldguard.com',     '2020-03-17', 'churned', 'enterprise'),
  (9,  'Growth Labs',        'finance@growthlabs.com',   '2023-09-14', 'active',  'pro'),
  (10, 'Moonshot Ventures',  'admin@moonshot.vc',        '2024-01-03', 'active',  'enterprise');

-- Orders
INSERT INTO orders (id, customer_id, total_cents, status, created_at) VALUES
  (1,  1,  250000, 'paid',      '2024-01-10 09:00:00+00'),
  (2,  1,   75000, 'paid',      '2024-03-05 14:30:00+00'),
  (3,  2,   49900, 'paid',      '2024-02-18 11:15:00+00'),
  (4,  2,   49900, 'refunded',  '2024-04-01 08:45:00+00'),
  (5,  3,       0, 'pending',   '2024-05-20 16:00:00+00'),
  (6,  4,   99800, 'paid',      '2023-01-25 10:00:00+00'),
  (7,  5,   49900, 'paid',      '2024-03-15 13:00:00+00'),
  (8,  5,   49900, 'paid',      '2024-06-01 09:30:00+00'),
  (9,  6,  500000, 'paid',      '2024-01-20 12:00:00+00'),
  (10, 6,  500000, 'paid',      '2024-04-20 12:00:00+00'),
  (11, 7,       0, 'pending',   '2024-06-10 17:00:00+00'),
  (12, 8,  250000, 'paid',      '2022-05-11 10:00:00+00'),
  (13, 9,   49900, 'paid',      '2024-02-01 08:00:00+00'),
  (14, 9,   49900, 'cancelled', '2024-05-15 11:00:00+00'),
  (15, 10, 500000, 'paid',      '2024-01-05 09:00:00+00');

-- Order items
INSERT INTO order_items (id, order_id, product, quantity, unit_cents) VALUES
  -- Order 1 (Acme Corp, enterprise)
  (1,  1,  'Platform License',   1, 200000),
  (2,  1,  'Support Add-on',     1,  50000),
  -- Order 2 (Acme Corp, renewal add-on)
  (3,  2,  'Extra Seats',        5,  15000),
  -- Order 3 (Bright Ideas, pro)
  (4,  3,  'Pro Subscription',   1,  49900),
  -- Order 4 (Bright Ideas, refunded)
  (5,  4,  'Pro Subscription',   1,  49900),
  -- Order 5 (Solo Dev, trial — no charge)
  (6,  5,  'Free Tier',          1,      0),
  -- Order 6 (Departed Ltd)
  (7,  6,  'Pro Subscription',   2,  49900),
  -- Order 7 (Startup House)
  (8,  7,  'Pro Subscription',   1,  49900),
  -- Order 8 (Startup House renewal)
  (9,  8,  'Pro Subscription',   1,  49900),
  -- Order 9 (Big Fish, enterprise)
  (10, 9,  'Platform License',   1, 200000),
  (11, 9,  'Support Add-on',     1,  50000),
  (12, 9,  'Extra Seats',       10,  25000),
  -- Order 10 (Big Fish, renewal)
  (13, 10, 'Platform License',   1, 200000),
  (14, 10, 'Support Add-on',     1,  50000),
  (15, 10, 'Extra Seats',       10,  25000),
  -- Order 11 (Tiny Shop, trial)
  (16, 11, 'Free Tier',          1,      0),
  -- Order 12 (Old Guard Co)
  (17, 12, 'Platform License',   1, 200000),
  (18, 12, 'Support Add-on',     1,  50000),
  -- Order 13 (Growth Labs)
  (19, 13, 'Pro Subscription',   1,  49900),
  -- Order 14 (Growth Labs, cancelled)
  (20, 14, 'Pro Subscription',   1,  49900),
  -- Order 15 (Moonshot Ventures, enterprise)
  (21, 15, 'Platform License',   1, 200000),
  (22, 15, 'Support Add-on',     1,  50000),
  (23, 15, 'Extra Seats',       10,  25000);
