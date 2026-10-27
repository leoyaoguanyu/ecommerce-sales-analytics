-- Q1. How is the business growing? Monthly GMV, orders, AOV,
--     month-over-month growth and a 3-month moving average.
WITH monthly AS (
    SELECT order_month,
           COUNT(*)                      AS orders,
           COUNT(DISTINCT customer_unique_id) AS customers,
           SUM(gmv)                      AS gmv
    FROM analytics.v_sales
    GROUP BY order_month
)
SELECT
    order_month,
    orders,
    customers,
    ROUND(gmv, 2)                                            AS gmv,
    ROUND(gmv / orders, 2)                                   AS aov,
    ROUND(100.0 * (gmv / LAG(gmv) OVER w - 1), 1)            AS gmv_mom_pct,
    ROUND(AVG(gmv) OVER (w ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2) AS gmv_3m_avg
FROM monthly
WINDOW w AS (ORDER BY order_month)
ORDER BY order_month;
