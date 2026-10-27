-- Q7. Which customers are most valuable? RFM segmentation.
--     Recency / Frequency / Monetary scored 1-5 with NTILE, then mapped to
--     named segments. Because ~97% of customers order once, frequency is
--     scored as 1 (one order) or 5 (repeat) instead of an NTILE.
--     Reference date = day after the last order in the window.
DROP TABLE IF EXISTS analytics.customer_rfm;
CREATE TABLE analytics.customer_rfm AS
WITH ref AS (
    SELECT MAX(order_date) + 1 AS ref_date FROM analytics.v_sales
),
base AS (
    SELECT s.customer_unique_id,
           (SELECT ref_date FROM ref) - MAX(s.order_date) AS recency_days,
           COUNT(*)                                       AS frequency,
           SUM(s.gmv)                                     AS monetary
    FROM analytics.v_sales s
    GROUP BY s.customer_unique_id
),
scored AS (
    SELECT *,
           NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,  -- recent = 5
           CASE WHEN frequency > 1 THEN 5 ELSE 1 END  AS f_score,
           NTILE(5) OVER (ORDER BY monetary)          AS m_score   -- high = 5
    FROM base
)
SELECT
    customer_unique_id,
    recency_days,
    frequency,
    ROUND(monetary, 2) AS monetary,
    r_score, f_score, m_score,
    CASE
        WHEN f_score = 5 AND r_score >= 4                 THEN 'Loyal - Active'
        WHEN f_score = 5                                  THEN 'Loyal - Lapsing'
        WHEN r_score >= 4 AND m_score >= 4                THEN 'New High-Value'
        WHEN r_score >= 4                                 THEN 'New Low-Value'
        WHEN r_score <= 2 AND m_score >= 4                THEN 'At-Risk High-Value'
        ELSE                                                   'Hibernating'
    END AS segment
FROM scored;
ALTER TABLE analytics.customer_rfm ADD PRIMARY KEY (customer_unique_id);

SELECT
    segment,
    COUNT(*)                                                 AS customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)       AS pct_customers,
    ROUND(SUM(monetary), 2)                                  AS gmv,
    ROUND(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 1) AS pct_gmv,
    ROUND(AVG(monetary), 2)                                  AS avg_spend,
    ROUND(AVG(recency_days), 0)                              AS avg_recency_days
FROM analytics.customer_rfm
GROUP BY segment
ORDER BY gmv DESC;
