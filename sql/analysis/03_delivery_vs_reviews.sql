-- Q3. Does late delivery hurt customer satisfaction?
--     Review score and share of 1-2 star reviews by delivery-delay bucket.
SELECT
    CASE
        WHEN days_late <= -10 THEN '1. 10+ days early'
        WHEN days_late <= 0   THEN '2. 0-9 days early'
        WHEN days_late <= 3   THEN '3. 1-3 days late'
        WHEN days_late <= 7   THEN '4. 4-7 days late'
        ELSE                       '5. 8+ days late'
    END                                                       AS delay_bucket,
    COUNT(*)                                                  AS orders,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)        AS pct_of_orders,
    ROUND(AVG(review_score), 2)                               AS avg_review,
    ROUND(100.0 * AVG(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END), 1) AS pct_negative_reviews
FROM analytics.v_sales
WHERE is_delivered AND review_score IS NOT NULL
GROUP BY delay_bucket
ORDER BY delay_bucket;
