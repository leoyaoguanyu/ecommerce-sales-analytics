-- 04_data_quality.sql
-- Data-quality report. "blocking" checks must return 0 rows or the
-- pipeline stops (run_pipeline.sh fails); "info" checks are documented
-- known issues in the source data that 03_clean.sql handles.

DROP TABLE IF EXISTS analytics.dq_report;
CREATE TABLE analytics.dq_report AS
SELECT 'blocking' AS severity, 'order rows lost in cleaning' AS check_name,
       (SELECT COUNT(*) FROM raw.orders) - (SELECT COUNT(*) FROM analytics.fct_orders) AS failing_rows
UNION ALL
SELECT 'blocking', 'order item rows lost in cleaning',
       (SELECT COUNT(*) FROM raw.order_items) - (SELECT COUNT(*) FROM analytics.fct_order_items)
UNION ALL
SELECT 'blocking', 'negative price or freight',
       (SELECT COUNT(*) FROM raw.order_items WHERE price < 0 OR freight_value < 0)
UNION ALL
SELECT 'blocking', 'delivered before purchase',
       (SELECT COUNT(*) FROM raw.orders
        WHERE order_delivered_customer_date < order_purchase_timestamp)
UNION ALL
SELECT 'blocking', 'order with more than one review after dedup',
       (SELECT COUNT(*) - COUNT(DISTINCT order_id) FROM analytics.fct_orders)
UNION ALL
SELECT 'info', 'delivered status but no delivery date',
       (SELECT COUNT(*) FROM raw.orders
        WHERE order_status = 'delivered' AND order_delivered_customer_date IS NULL)
UNION ALL
SELECT 'info', 'valid orders with no items',
       (SELECT COUNT(*) FROM analytics.fct_orders WHERE is_valid_sale AND item_count = 0)
UNION ALL
SELECT 'info', 'orders where payment differs from GMV by > 1',
       (SELECT COUNT(*) FROM analytics.fct_orders
        WHERE item_count > 0 AND ABS(payment_value - gmv) > 1)
UNION ALL
SELECT 'info', 'duplicate review rows removed',
       (SELECT COUNT(*) FROM raw.order_reviews)
       - (SELECT COUNT(*) FROM analytics.fct_orders WHERE review_score IS NOT NULL)
UNION ALL
SELECT 'info', 'products with no category',
       (SELECT COUNT(*) FROM raw.products WHERE product_category_name IS NULL);

SELECT * FROM analytics.dq_report ORDER BY severity, check_name;
