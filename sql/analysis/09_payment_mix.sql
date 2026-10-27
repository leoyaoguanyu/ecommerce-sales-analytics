-- Q9. How do customers pay? Payment-type mix and whether paying in
--     instalments is associated with larger baskets.
SELECT
    payment_type,
    CASE WHEN max_installments <= 1 THEN '1 (single payment)'
         WHEN max_installments <= 3 THEN '2-3'
         WHEN max_installments <= 6 THEN '4-6'
         ELSE '7+' END                                        AS installments,
    COUNT(*)                                                  AS orders,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)        AS pct_orders,
    ROUND(AVG(gmv), 2)                                        AS aov
FROM analytics.v_sales
WHERE payment_type IS NOT NULL
GROUP BY payment_type, installments
ORDER BY payment_type, installments;
