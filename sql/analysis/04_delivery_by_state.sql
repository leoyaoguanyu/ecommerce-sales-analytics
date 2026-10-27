-- Q4. Where are deliveries slowest? Delivery time, late rate and review
--     score by customer state (states with at least 500 delivered orders).
SELECT
    c.customer_state,
    COUNT(*)                                                  AS delivered_orders,
    ROUND(AVG(s.delivery_days), 1)                            AS avg_delivery_days,
    ROUND(AVG(s.promised_days), 1)                            AS avg_promised_days,
    ROUND(100.0 * AVG(CASE WHEN s.is_late THEN 1 ELSE 0 END), 1) AS late_rate_pct,
    ROUND(AVG(s.review_score), 2)                             AS avg_review,
    RANK() OVER (ORDER BY AVG(CASE WHEN s.is_late THEN 1 ELSE 0 END) DESC) AS late_rank
FROM analytics.v_sales s
JOIN analytics.dim_customer c USING (customer_unique_id)
WHERE s.is_delivered
GROUP BY c.customer_state
HAVING COUNT(*) >= 500
ORDER BY late_rate_pct DESC;
