-- Q5. Do customers come back? Repeat-purchase rate overall, and the
--     share of revenue that comes from repeat customers.
WITH per_customer AS (
    SELECT customer_unique_id,
           COUNT(*)  AS orders,
           SUM(gmv)  AS gmv
    FROM analytics.v_sales
    GROUP BY customer_unique_id
)
SELECT
    COUNT(*)                                                       AS customers,
    SUM(CASE WHEN orders > 1 THEN 1 ELSE 0 END)                    AS repeat_customers,
    ROUND(100.0 * AVG(CASE WHEN orders > 1 THEN 1 ELSE 0 END), 2)  AS repeat_rate_pct,
    ROUND(AVG(orders), 3)                                          AS avg_orders_per_customer,
    ROUND(100.0 * SUM(CASE WHEN orders > 1 THEN gmv ELSE 0 END) / SUM(gmv), 2)
                                                                   AS repeat_gmv_share_pct
FROM per_customer;
