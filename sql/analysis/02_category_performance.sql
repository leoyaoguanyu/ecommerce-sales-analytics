-- Q2. Which product categories drive revenue, and how satisfied are
--     their customers? Revenue share, cumulative share (Pareto), rank,
--     average review and late-delivery rate per category.
WITH cat AS (
    SELECT oi.category,
           COUNT(DISTINCT oi.order_id)                       AS orders,
           SUM(oi.line_gmv)                                  AS gmv,
           AVG(s.review_score)                               AS avg_review,
           AVG(CASE WHEN s.is_late THEN 1.0
                    WHEN s.is_late = FALSE THEN 0.0 END)     AS late_rate
    FROM analytics.fct_order_items oi
    JOIN analytics.v_sales s USING (order_id)
    GROUP BY oi.category
)
SELECT
    RANK() OVER (ORDER BY gmv DESC)                          AS revenue_rank,
    category,
    orders,
    ROUND(gmv, 2)                                            AS gmv,
    ROUND(100.0 * gmv / SUM(gmv) OVER (), 2)                 AS gmv_share_pct,
    ROUND(100.0 * SUM(gmv) OVER (ORDER BY gmv DESC)
                / SUM(gmv) OVER (), 1)                       AS cumulative_share_pct,
    ROUND(avg_review, 2)                                     AS avg_review,
    ROUND(100.0 * late_rate, 1)                              AS late_rate_pct
FROM cat
ORDER BY revenue_rank;
