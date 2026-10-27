-- Q6. Monthly cohort retention: of customers whose first purchase was in
--     month M, what % bought again 1, 2, 3 ... months later?
WITH first_purchase AS (
    SELECT customer_unique_id,
           MIN(order_month) AS cohort_month
    FROM analytics.v_sales
    GROUP BY customer_unique_id
),
activity AS (
    SELECT DISTINCT
           f.cohort_month,
           s.customer_unique_id,
           (EXTRACT(YEAR  FROM AGE(s.order_month, f.cohort_month)) * 12
          + EXTRACT(MONTH FROM AGE(s.order_month, f.cohort_month)))::int AS month_number
    FROM analytics.v_sales s
    JOIN first_purchase f USING (customer_unique_id)
),
cohort_size AS (
    SELECT cohort_month, COUNT(*) AS cohort_customers
    FROM first_purchase
    GROUP BY cohort_month
)
SELECT
    a.cohort_month,
    c.cohort_customers,
    a.month_number,
    COUNT(*)                                             AS active_customers,
    ROUND(100.0 * COUNT(*) / c.cohort_customers, 2)      AS retention_pct
FROM activity a
JOIN cohort_size c USING (cohort_month)
WHERE a.month_number BETWEEN 0 AND 12
GROUP BY a.cohort_month, c.cohort_customers, a.month_number
ORDER BY a.cohort_month, a.month_number;
