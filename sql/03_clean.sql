-- 03_clean.sql
-- Analytics layer: cleaned star schema used by every analysis query
-- and exported for the Power BI model.
--
-- Business rules (documented in README):
--   * Revenue (GMV) = item price + freight, for orders that were not
--     'canceled' or 'unavailable'.
--   * Analysis window = complete months 2017-01 .. 2018-08
--     (2016 and Sep/Oct 2018 have only a handful of orders).
--   * A customer is customer_unique_id (customer_id is per-order in Olist).
--   * One review per order: the most recently answered review is kept.

DROP SCHEMA IF EXISTS analytics CASCADE;
CREATE SCHEMA analytics;

-- ---------------------------------------------------------------- dims
CREATE TABLE analytics.dim_product AS
SELECT
    p.product_id,
    -- 610 products have no category; 2 categories have no translation
    COALESCE(t.product_category_name_english,
             p.product_category_name,
             'unknown')                                  AS category,
    p.product_weight_g,
    p.product_photos_qty
FROM raw.products p
LEFT JOIN raw.category_translation t USING (product_category_name);
ALTER TABLE analytics.dim_product ADD PRIMARY KEY (product_id);

CREATE TABLE analytics.dim_seller AS
SELECT seller_id, seller_city, seller_state FROM raw.sellers;
ALTER TABLE analytics.dim_seller ADD PRIMARY KEY (seller_id);

-- Customer state taken from the customer's first order.
CREATE TABLE analytics.dim_customer AS
SELECT DISTINCT ON (c.customer_unique_id)
    c.customer_unique_id,
    c.customer_city,
    c.customer_state
FROM raw.customers c
JOIN raw.orders o USING (customer_id)
ORDER BY c.customer_unique_id, o.order_purchase_timestamp;
ALTER TABLE analytics.dim_customer ADD PRIMARY KEY (customer_unique_id);

-- ---------------------------------------------------------------- facts
CREATE TABLE analytics.fct_orders AS
WITH items AS (
    SELECT order_id,
           COUNT(*)           AS item_count,
           SUM(price)         AS item_revenue,
           SUM(freight_value) AS freight_revenue
    FROM raw.order_items
    GROUP BY order_id
),
payments AS (
    SELECT order_id,
           SUM(payment_value)        AS payment_value,
           MAX(payment_installments) AS max_installments,
           -- primary payment type = the largest payment on the order
           (ARRAY_AGG(payment_type ORDER BY payment_value DESC))[1] AS payment_type
    FROM raw.order_payments
    GROUP BY order_id
),
reviews AS (
    SELECT DISTINCT ON (order_id) order_id, review_score
    FROM raw.order_reviews
    ORDER BY order_id, review_answer_timestamp DESC
)
SELECT
    o.order_id,
    c.customer_unique_id,
    o.order_status,
    o.order_purchase_timestamp,
    o.order_purchase_timestamp::date                         AS order_date,
    DATE_TRUNC('month', o.order_purchase_timestamp)::date    AS order_month,
    COALESCE(i.item_count, 0)                                AS item_count,
    COALESCE(i.item_revenue, 0)                              AS item_revenue,
    COALESCE(i.freight_revenue, 0)                           AS freight_revenue,
    COALESCE(i.item_revenue, 0) + COALESCE(i.freight_revenue, 0) AS gmv,
    p.payment_value,
    p.payment_type,
    p.max_installments,
    o.order_status NOT IN ('canceled', 'unavailable')        AS is_valid_sale,
    o.order_status = 'delivered'
        AND o.order_delivered_customer_date IS NOT NULL      AS is_delivered,
    ROUND(EXTRACT(EPOCH FROM o.order_delivered_customer_date
                           - o.order_purchase_timestamp) / 86400.0, 1) AS delivery_days,
    ROUND(EXTRACT(EPOCH FROM o.order_estimated_delivery_date
                           - o.order_purchase_timestamp) / 86400.0, 1) AS promised_days,
    -- days late vs. the promised date (negative = early); compared on dates
    (o.order_delivered_customer_date::date
       - o.order_estimated_delivery_date::date)              AS days_late,
    r.review_score
FROM raw.orders o
JOIN raw.customers c   USING (customer_id)
LEFT JOIN items i      USING (order_id)
LEFT JOIN payments p   USING (order_id)
LEFT JOIN reviews r    USING (order_id);
ALTER TABLE analytics.fct_orders ADD PRIMARY KEY (order_id);

ALTER TABLE analytics.fct_orders ADD COLUMN is_late BOOLEAN;
UPDATE analytics.fct_orders
SET is_late = CASE WHEN is_delivered THEN days_late > 0 END;

ALTER TABLE analytics.fct_orders ADD COLUMN in_window BOOLEAN;
UPDATE analytics.fct_orders
SET in_window = order_month BETWEEN DATE '2017-01-01' AND DATE '2018-08-01';

CREATE TABLE analytics.fct_order_items AS
SELECT
    oi.order_id,
    oi.order_item_id,
    oi.product_id,
    oi.seller_id,
    dp.category,
    oi.price,
    oi.freight_value,
    oi.price + oi.freight_value AS line_gmv
FROM raw.order_items oi
JOIN analytics.dim_product dp USING (product_id);
ALTER TABLE analytics.fct_order_items ADD PRIMARY KEY (order_id, order_item_id);

CREATE INDEX ON analytics.fct_orders (customer_unique_id);
CREATE INDEX ON analytics.fct_orders (order_month);
CREATE INDEX ON analytics.fct_order_items (product_id);
CREATE INDEX ON analytics.fct_order_items (seller_id);

-- Convenience view: the population almost every analysis uses.
CREATE VIEW analytics.v_sales AS
SELECT * FROM analytics.fct_orders
WHERE is_valid_sale AND in_window AND item_count > 0;

ANALYZE;
