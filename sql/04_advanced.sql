-- Q1. Cohort Retention Analysis
-- months_since = year*12+month diff, not AGE() — AGE() wraps at 12mo
WITH first_purchase AS (
    SELECT
        c.customer_unique_id,
        DATE_TRUNC('month', MIN(o.order_purchase_timestamp))::DATE AS cohort_month
    FROM olist.customers c
    JOIN olist.orders o ON c.customer_id = o.customer_id
    GROUP BY c.customer_unique_id
),
order_months AS (
    SELECT DISTINCT
        c.customer_unique_id,
        DATE_TRUNC('month', o.order_purchase_timestamp)::DATE AS order_month
    FROM olist.customers c
    JOIN olist.orders o ON c.customer_id = o.customer_id
),
cohort_activity AS (
    SELECT
        fp.cohort_month,
        om.order_month,
        (EXTRACT(YEAR FROM om.order_month)  - EXTRACT(YEAR FROM fp.cohort_month)) * 12
      + (EXTRACT(MONTH FROM om.order_month) - EXTRACT(MONTH FROM fp.cohort_month))
            AS months_since,
        om.customer_unique_id
    FROM first_purchase fp
    JOIN order_months om ON fp.customer_unique_id = om.customer_unique_id
),
cohort_sizes AS (
    SELECT
        cohort_month,
        COUNT(DISTINCT customer_unique_id) AS cohort_size
    FROM first_purchase
    GROUP BY cohort_month
)
SELECT
    ca.cohort_month,
    cs.cohort_size,
    ca.months_since,
    COUNT(DISTINCT ca.customer_unique_id) AS active_customers,
    ROUND(
        COUNT(DISTINCT ca.customer_unique_id) * 100.0 / cs.cohort_size, 2
    ) AS retention_rate
FROM cohort_activity ca
JOIN cohort_sizes cs ON ca.cohort_month = cs.cohort_month
GROUP BY ca.cohort_month, cs.cohort_size, ca.months_since
ORDER BY ca.cohort_month, ca.months_since;


-- Q2. Customer Lifetime Value (CLV)
-- ROWS UNBOUNDED PRECEDING + order_id tiebreak for same-timestamp orders
WITH order_revenue AS (
    SELECT
        o.order_id,
        c.customer_unique_id,
        o.order_purchase_timestamp,
        SUM(p.payment_value) AS order_revenue
    FROM olist.orders o
    JOIN olist.customers      c ON o.customer_id = c.customer_id
    JOIN olist.order_payments  p ON o.order_id    = p.order_id
    GROUP BY o.order_id, c.customer_unique_id, o.order_purchase_timestamp
)
SELECT
    customer_unique_id,
    order_id,
    order_purchase_timestamp,
    ROUND(order_revenue, 2)        AS order_revenue,
    ROUND(
        SUM(order_revenue) OVER (
            PARTITION BY customer_unique_id
            ORDER BY order_purchase_timestamp, order_id
            ROWS UNBOUNDED PRECEDING
        ), 2
    )                              AS cumulative_revenue,
    ROW_NUMBER() OVER (
        PARTITION BY customer_unique_id
        ORDER BY order_purchase_timestamp, order_id
    )                              AS order_sequence
FROM order_revenue
ORDER BY customer_unique_id, order_purchase_timestamp, order_id;


-- Q3. RFM Segmentation
-- recency flipped via 6-NTILE(5) so 5=most recent; NTILE on 1-order-heavy frequency inflates upper segments
WITH reference AS (
    SELECT MAX(order_purchase_timestamp) AS ref_date
    FROM olist.orders
),
customer_rfm_raw AS (
    SELECT
        c.customer_unique_id,
        EXTRACT(DAY FROM (ref.ref_date - MAX(o.order_purchase_timestamp)))::INT
            AS recency_days,
        COUNT(DISTINCT o.order_id)  AS frequency,
        ROUND(SUM(p.payment_value), 2) AS monetary
    FROM olist.customers c
    JOIN olist.orders         o ON c.customer_id = o.customer_id
    JOIN olist.order_payments p ON o.order_id    = p.order_id
    CROSS JOIN reference ref
    GROUP BY c.customer_unique_id, ref.ref_date
),
rfm_scored AS (
    SELECT
        customer_unique_id,
        recency_days,
        frequency,
        monetary,
        6 - NTILE(5) OVER (ORDER BY recency_days ASC) AS r_score,
        NTILE(5) OVER (ORDER BY frequency ASC)         AS f_score,
        NTILE(5) OVER (ORDER BY monetary ASC)          AS m_score
    FROM customer_rfm_raw
)
SELECT
    customer_unique_id,
    recency_days,
    frequency,
    monetary,
    r_score,
    f_score,
    m_score,
    CASE
        WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4
            THEN 'Champions'
        WHEN f_score >= 3 AND m_score >= 3
            THEN 'Loyal Customers'
        WHEN r_score >= 3 AND f_score >= 2 AND m_score >= 2
            THEN 'Potential Loyalists'
        WHEN r_score >= 4 AND f_score <= 2
            THEN 'New Customers'
        WHEN r_score >= 3 AND f_score <= 2 AND m_score <= 2
            THEN 'Promising'
        WHEN r_score = 3 AND f_score = 3 AND m_score = 3
            THEN 'Need Attention'
        WHEN r_score = 2 AND f_score >= 2
            THEN 'About to Sleep'
        WHEN r_score <= 2 AND f_score >= 3 AND m_score >= 3
            THEN 'At Risk'
        WHEN r_score <= 2 AND f_score >= 4 AND m_score >= 4
            THEN 'Can''t Lose Them'
        WHEN r_score <= 2 AND f_score <= 2
            THEN 'Hibernating'
        WHEN r_score = 1 AND f_score = 1 AND m_score = 1
            THEN 'Lost'
        ELSE 'Others'
    END AS segment
FROM rfm_scored
ORDER BY monetary DESC;


-- Q4. Churn Detection
-- only meaningful for 2+ orders; this is a snapshot flag, not a prediction
WITH reference AS (
    SELECT MAX(order_purchase_timestamp) AS ref_date
    FROM olist.orders
),
customer_orders AS (
    SELECT
        c.customer_unique_id,
        o.order_id,
        o.order_purchase_timestamp,
        LAG(o.order_purchase_timestamp) OVER (
            PARTITION BY c.customer_unique_id
            ORDER BY o.order_purchase_timestamp, o.order_id
        ) AS prev_order_timestamp
    FROM olist.customers c
    JOIN olist.orders o ON c.customer_id = o.customer_id
),
order_gaps AS (
    SELECT
        customer_unique_id,
        order_id,
        order_purchase_timestamp,
        EXTRACT(DAY FROM (order_purchase_timestamp - prev_order_timestamp))::INT
            AS days_since_prev
    FROM customer_orders
    WHERE prev_order_timestamp IS NOT NULL
),
customer_cadence AS (
    SELECT
        og.customer_unique_id,
        COUNT(*) + 1                            AS order_count,
        ROUND(AVG(og.days_since_prev), 1)       AS avg_days_between,
        MAX(co.order_purchase_timestamp)         AS last_order_date,
        EXTRACT(DAY FROM (ref.ref_date - MAX(co.order_purchase_timestamp)))::INT
                                                AS days_since_last,
        ROUND(AVG(og.days_since_prev) * 1.5, 1) AS churn_threshold
    FROM order_gaps og
    JOIN customer_orders co ON og.customer_unique_id = co.customer_unique_id
    CROSS JOIN reference ref
    GROUP BY og.customer_unique_id, ref.ref_date
)
SELECT
    customer_unique_id,
    order_count,
    avg_days_between,
    last_order_date,
    days_since_last,
    churn_threshold,
    CASE
        WHEN days_since_last > churn_threshold THEN true
        ELSE false
    END AS is_churned
FROM customer_cadence
ORDER BY days_since_last DESC;


-- Q5. Delivery Performance vs. Customer Satisfaction
-- delta = actual - estimated; delivered orders only, non-null dates
WITH delivery_data AS (
    SELECT
        o.order_id,
        o.order_purchase_timestamp,
        o.order_estimated_delivery_date,
        o.order_delivered_customer_date,
        EXTRACT(DAY FROM (
            o.order_delivered_customer_date - o.order_estimated_delivery_date
        ))::INT AS delivery_delta_days,
        r.review_score
    FROM olist.orders o
    LEFT JOIN olist.order_reviews r ON o.order_id = r.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
)
SELECT
    CASE
        WHEN delivery_delta_days < 0  THEN 'Early'
        WHEN delivery_delta_days = 0  THEN 'On-Time'
        WHEN delivery_delta_days <= 7 THEN 'Late (1–7 days)'
        ELSE                               'Late (>7 days)'
    END                                  AS delivery_bucket,
    COUNT(*)                             AS order_count,
    ROUND(COUNT(*) * 100.0 /
        SUM(COUNT(*)) OVER (), 1)        AS pct_of_total,
    ROUND(AVG(delivery_delta_days), 1)   AS avg_delta_days,
    ROUND(AVG(review_score), 2)          AS avg_review_score,
    ROUND(MIN(review_score)::NUMERIC, 2) AS min_review,
    ROUND(MAX(review_score)::NUMERIC, 2) AS max_review
FROM delivery_data
GROUP BY
    CASE
        WHEN delivery_delta_days < 0  THEN 'Early'
        WHEN delivery_delta_days = 0  THEN 'On-Time'
        WHEN delivery_delta_days <= 7 THEN 'Late (1–7 days)'
        ELSE                               'Late (>7 days)'
    END
ORDER BY MIN(delivery_delta_days);
