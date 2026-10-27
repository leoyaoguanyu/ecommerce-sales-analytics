-- Q8. How concentrated is revenue among sellers? Pareto analysis:
--     what share of GMV comes from the top 10% / 20% of sellers?
WITH seller_gmv AS (
    SELECT oi.seller_id, SUM(oi.line_gmv) AS gmv
    FROM analytics.fct_order_items oi
    JOIN analytics.v_sales s USING (order_id)
    GROUP BY oi.seller_id
),
ranked AS (
    SELECT seller_id, gmv,
           PERCENT_RANK() OVER (ORDER BY gmv DESC) AS pct_rank
    FROM seller_gmv
)
SELECT
    tier,
    COUNT(*)                                             AS sellers,
    ROUND(SUM(gmv), 2)                                   AS gmv,
    ROUND(100.0 * SUM(gmv) / SUM(SUM(gmv)) OVER (), 1)   AS pct_gmv
FROM (
    SELECT gmv,
           CASE WHEN pct_rank < 0.10 THEN '1. Top 10%'
                WHEN pct_rank < 0.20 THEN '2. Next 10%'
                WHEN pct_rank < 0.50 THEN '3. Next 30%'
                ELSE                      '4. Bottom 50%' END AS tier
    FROM ranked
) t
GROUP BY tier
ORDER BY tier;
