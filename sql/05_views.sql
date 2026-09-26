-- Views for the Streamlit dashboard
-- Each view wraps one Phase 4 analytical query so the dashboard reads via
-- SELECT * FROM olist.v_<name> — zero logic in Python.

-- 1. Cohort Retention
CREATE OR REPLACE VIEW olist.v_cohort_retention AS
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
    ca.months_since::INT,
    COUNT(DISTINCT ca.customer_unique_id) AS active_customers,
    ROUND(
        COUNT(DISTINCT ca.customer_unique_id) * 100.0 / cs.cohort_size, 2
    ) AS retention_rate
FROM cohort_activity ca
JOIN cohort_sizes cs ON ca.cohort_month = cs.cohort_month
GROUP BY ca.cohort_month, cs.cohort_size, ca.months_since;


-- 2. Customer Lifetime Value
CREATE OR REPLACE VIEW olist.v_clv AS
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
FROM order_revenue;


-- 3. RFM Segments
CREATE OR REPLACE VIEW olist.v_rfm_segments AS
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
        WHEN r_score <= 2 AND f_score >= 4 AND m_score >= 4
            THEN 'Can''t Lose Them'
        WHEN r_score = 3 AND f_score = 3 AND m_score = 3
            THEN 'Need Attention'
        WHEN r_score <= 2 AND f_score >= 3 AND m_score >= 3
            THEN 'At Risk'
        WHEN f_score >= 3 AND m_score >= 3
            THEN 'Loyal Customers'
        WHEN r_score >= 3 AND f_score >= 2 AND m_score >= 2
            THEN 'Potential Loyalists'
        WHEN r_score >= 4 AND f_score <= 2
            THEN 'New Customers'
        WHEN r_score >= 3 AND f_score <= 2 AND m_score <= 2
            THEN 'Promising'
        WHEN r_score = 1 AND f_score = 1 AND m_score = 1
            THEN 'Lost'
        WHEN r_score = 2 AND f_score >= 2
            THEN 'About to Sleep'
        WHEN r_score <= 2 AND f_score <= 2
            THEN 'Hibernating'
        ELSE 'Others'
    END AS segment
FROM rfm_scored;


-- 4. Churn Risk
CREATE OR REPLACE VIEW olist.v_churn_risk AS
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
customer_summary AS (
    SELECT
        customer_unique_id,
        COUNT(*)                      AS order_count,
        MAX(order_purchase_timestamp) AS last_order_date
    FROM customer_orders
    GROUP BY customer_unique_id
),
gap_stats AS (
    SELECT
        customer_unique_id,
        ROUND(AVG(days_since_prev), 1) AS avg_days_between
    FROM order_gaps
    GROUP BY customer_unique_id
),
customer_cadence AS (
    SELECT
        cs.customer_unique_id,
        cs.order_count,
        gs.avg_days_between,
        cs.last_order_date,
        EXTRACT(DAY FROM (ref.ref_date - cs.last_order_date))::INT
            AS days_since_last,
        ROUND(gs.avg_days_between * 1.5, 1) AS churn_threshold
    FROM customer_summary cs
    JOIN gap_stats gs ON cs.customer_unique_id = gs.customer_unique_id
    CROSS JOIN reference ref
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
FROM customer_cadence;


-- 5. Delivery Performance
CREATE OR REPLACE VIEW olist.v_delivery_performance AS
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
    ROUND(AVG(review_score), 2)          AS avg_review_score
FROM delivery_data
GROUP BY
    CASE
        WHEN delivery_delta_days < 0  THEN 'Early'
        WHEN delivery_delta_days = 0  THEN 'On-Time'
        WHEN delivery_delta_days <= 7 THEN 'Late (1–7 days)'
        ELSE                               'Late (>7 days)'
    END;
