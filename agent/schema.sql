-- Curated database schema for the text2sql agent.
--
-- This file is injected verbatim into the agent's system prompt at startup.
-- It is the single most important input for SQL accuracy, so keep it:
--   * accurate     - match the real Postgres schema (regenerate after migrations)
--   * annotated    - comments carry the business meaning the model can't guess
--   * value-hinted - list distinct values for low-cardinality columns, so the
--                    model maps words like "churned" to status = 'churned'
--   * joinable     - keep FOREIGN KEY lines; they tell the model how to join
--
-- Replace the example tables below with your own. To bootstrap from a live DB:
--   pg_dump --schema-only --no-owner --no-privileges "$DATABASE_URL"
-- then trim it down and add comments + sample values by hand.

-- Customer accounts. One row per account.
CREATE TABLE customers (
  id          bigint PRIMARY KEY,
  name        text        NOT NULL,
  email       text        NOT NULL,
  signup_date date        NOT NULL,
  status      text        NOT NULL,  -- one of: 'trial', 'active', 'churned'
  plan        text        NOT NULL   -- one of: 'free', 'pro', 'enterprise'
);

-- Orders placed by customers. One row per order.
CREATE TABLE orders (
  id          bigint PRIMARY KEY,
  customer_id bigint      NOT NULL REFERENCES customers(id),  -- FK -> customers.id
  total_cents int         NOT NULL,  -- order total in cents; divide by 100 for dollars
  status      text        NOT NULL,  -- one of: 'pending', 'paid', 'refunded', 'cancelled'
  created_at  timestamptz NOT NULL
);

-- Line items within an order. One row per product line.
CREATE TABLE order_items (
  id         bigint PRIMARY KEY,
  order_id   bigint NOT NULL REFERENCES orders(id),  -- FK -> orders.id
  product    text   NOT NULL,
  quantity   int    NOT NULL,
  unit_cents int    NOT NULL  -- price per unit in cents
);
