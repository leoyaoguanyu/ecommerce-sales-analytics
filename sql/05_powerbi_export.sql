-- 05_powerbi_export.sql
-- Export the star schema to CSV for Power BI (Get Data -> Text/CSV).
-- Facts are limited to the analysis window and valid sales so the
-- dashboard numbers match the SQL analyses exactly.

\copy (SELECT order_id, customer_unique_id, order_date, order_month, order_status, item_count, item_revenue, freight_revenue, gmv, payment_type, max_installments, is_delivered::int AS is_delivered, delivery_days, promised_days, days_late, is_late::int AS is_late, CASE WHEN NOT is_delivered THEN NULL WHEN days_late <= -10 THEN '1. 10+ days early' WHEN days_late <= 0 THEN '2. 0-9 days early' WHEN days_late <= 3 THEN '3. 1-3 days late' WHEN days_late <= 7 THEN '4. 4-7 days late' ELSE '5. 8+ days late' END AS delay_bucket, review_score FROM analytics.v_sales ORDER BY order_date, order_id) TO 'powerbi/data/fct_orders.csv' WITH (FORMAT csv, HEADER true)

\copy (SELECT oi.order_id, oi.order_item_id, oi.product_id, oi.seller_id, oi.price, oi.freight_value, oi.line_gmv FROM analytics.fct_order_items oi JOIN analytics.v_sales s USING (order_id) ORDER BY oi.order_id, oi.order_item_id) TO 'powerbi/data/fct_order_items.csv' WITH (FORMAT csv, HEADER true)

\copy (SELECT c.customer_unique_id, c.customer_city, c.customer_state, r.recency_days, r.frequency, r.monetary, r.r_score, r.f_score, r.m_score, r.segment FROM analytics.dim_customer c JOIN analytics.customer_rfm r USING (customer_unique_id)) TO 'powerbi/data/dim_customer.csv' WITH (FORMAT csv, HEADER true)

\copy (SELECT product_id, category, product_weight_g, product_photos_qty FROM analytics.dim_product) TO 'powerbi/data/dim_product.csv' WITH (FORMAT csv, HEADER true)

\copy (SELECT seller_id, seller_city, seller_state FROM analytics.dim_seller) TO 'powerbi/data/dim_seller.csv' WITH (FORMAT csv, HEADER true)
