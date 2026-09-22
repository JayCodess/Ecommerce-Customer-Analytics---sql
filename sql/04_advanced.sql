-- =============================================================================
-- Olist E-Commerce Analytics — Phase 4: Advanced SQL
-- =============================================================================
-- Five analytical queries demonstrating window functions, CTEs, LAG/LEAD,
-- NTILE scoring, and complex CASE logic.
--
-- All queries use customer_unique_id as the person-level key (not customer_id,
-- which changes per order) — see NOTES.md entry #3.
--
-- Usable data window: ~Oct 2016 – Aug 2018 (see NOTES.md entry #9).
--
-- Run: psql -U postgres -d olist_ecommerce -f sql/04_advanced.sql
-- =============================================================================


-- ---------------------------------------------------------------------------
-- Q1. Cohort Retention Analysis
-- ---------------------------------------------------------------------------
-- Assigns each customer to an acquisition cohort (month of first purchase),
-- then tracks how many return in subsequent months.
--
-- Key decisions:
--   - Cohort = DATE_TRUNC('month', first_purchase) per customer_unique_id
--   - months_since uses year×12 + month arithmetic, NOT DATE_PART('month',
--     AGE(...)) which silently wraps at 12 and gives wrong results for gaps
--     spanning year boundaries
--   - retention_rate = active_customers / cohort_size (the month-0 count)
--
-- Output: one row per (cohort_month, months_since) pair — pivotable into a
-- retention heatmap in Phase 6.

WITH first_purchase AS (
    -- Step 1: find each customer's first-ever order month
    SELECT
        c.customer_unique_id,
        DATE_TRUNC('month', MIN(o.order_purchase_timestamp))::DATE AS cohort_month
    FROM olist.customers c
    JOIN olist.orders o ON c.customer_id = o.customer_id
    GROUP BY c.customer_unique_id
),
order_months AS (
    -- Step 2: all (customer, order_month) pairs
    SELECT DISTINCT
        c.customer_unique_id,
        DATE_TRUNC('month', o.order_purchase_timestamp)::DATE AS order_month
    FROM olist.customers c
    JOIN olist.orders o ON c.customer_id = o.customer_id
),
cohort_activity AS (
    -- Step 3: compute months_since for each customer–month touchpoint
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
    -- Step 4: count of customers per cohort (month-0 baseline)
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


-- ---------------------------------------------------------------------------
-- Q2. Customer Lifetime Value (CLV)
-- ---------------------------------------------------------------------------
-- Computes a running cumulative revenue per customer, ordered by purchase
-- date. Each row shows one order and the customer's total spend up to and
-- including that order.
--
-- Revenue source: SUM(payment_value) per order from order_payments (captures
-- actual amounts charged, including freight — see NOTES.md entry #5).
--
-- Window: SUM() OVER (PARTITION BY customer ORDER BY date ROWS UNBOUNDED
-- PRECEDING) gives a deterministic running total even when two orders share
-- the same timestamp.

WITH order_revenue AS (
    -- Aggregate payment rows to one revenue figure per order
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


-- ---------------------------------------------------------------------------
-- Q3. RFM Segmentation
-- ---------------------------------------------------------------------------
-- Recency, Frequency, Monetary scoring per customer_unique_id:
--   R = days since last order (lower = better)
--   F = count of distinct orders (higher = better)
--   M = total lifetime spend (higher = better)
--
-- Each dimension scored 1–5 via NTILE(5). For Recency, the scoring is
-- reversed (NTILE gives 1 to the oldest group; we flip so 5 = most recent).
--
-- Segment labels use an exhaustive CASE on (R, F, M) score ranges, adapted
-- from standard RFM literature. An "Others" catch-all ensures no customer
-- falls through.
--
-- Reference date: MAX(order_purchase_timestamp) from the dataset — treated
-- as "today" since the dataset is a closed historical window.

WITH reference AS (
    SELECT MAX(order_purchase_timestamp) AS ref_date
    FROM olist.orders
),
customer_rfm_raw AS (
    SELECT
        c.customer_unique_id,
        -- Recency: days since last order
        EXTRACT(DAY FROM (ref.ref_date - MAX(o.order_purchase_timestamp)))::INT
            AS recency_days,
        -- Frequency: number of distinct orders
        COUNT(DISTINCT o.order_id)  AS frequency,
        -- Monetary: total lifetime spend
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
        -- Recency: NTILE gives 1 to smallest (most recent) group, so
        -- 6 - ntile flips it: 5 = most recent, 1 = most stale
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
        -- Champions: recent, frequent, high-value
        WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4
            THEN 'Champions'
        -- Loyal Customers: frequent and high-value (recency may vary)
        WHEN f_score >= 3 AND m_score >= 3
            THEN 'Loyal Customers'
        -- Potential Loyalists: recent, moderate frequency
        WHEN r_score >= 3 AND f_score >= 2 AND m_score >= 2
            THEN 'Potential Loyalists'
        -- New Customers: very recent but low frequency
        WHEN r_score >= 4 AND f_score <= 2
            THEN 'New Customers'
        -- Promising: recent, low frequency, low-mid monetary
        WHEN r_score >= 3 AND f_score <= 2 AND m_score <= 2
            THEN 'Promising'
        -- Need Attention: mid-range across the board
        WHEN r_score = 3 AND f_score = 3 AND m_score = 3
            THEN 'Need Attention'
        -- About to Sleep: below-average recency, previously active
        WHEN r_score = 2 AND f_score >= 2
            THEN 'About to Sleep'
        -- At Risk: haven't purchased recently but were frequent/high-value
        WHEN r_score <= 2 AND f_score >= 3 AND m_score >= 3
            THEN 'At Risk'
        -- Can't Lose Them: formerly high-value, now lapsed
        WHEN r_score <= 2 AND f_score >= 4 AND m_score >= 4
            THEN 'Can''t Lose Them'
        -- Hibernating: low recency, low frequency
        WHEN r_score <= 2 AND f_score <= 2
            THEN 'Hibernating'
        -- Lost: worst across all dimensions
        WHEN r_score = 1 AND f_score = 1 AND m_score = 1
            THEN 'Lost'
        ELSE 'Others'
    END AS segment
FROM rfm_scored
ORDER BY monetary DESC;


-- ---------------------------------------------------------------------------
-- Q4. Churn Detection
-- ---------------------------------------------------------------------------
-- Identifies customers likely to have churned by comparing how long it's
-- been since their last order against their personal purchase cadence.
--
-- Logic:
--   1. LAG() computes the gap (in days) between consecutive orders per
--      customer.
--   2. Average those gaps → avg_days_between_orders (personal cadence).
--   3. days_since_last = reference_date - last order date.
--   4. churn_threshold = 1.5 × avg_days_between. If days_since_last exceeds
--      this, the customer is flagged as churned.
--
-- Only meaningful for customers with ≥ 2 orders — single-purchase customers
-- have no cadence to measure against and are excluded.

WITH reference AS (
    SELECT MAX(order_purchase_timestamp) AS ref_date
    FROM olist.orders
),
customer_orders AS (
    -- Deduplicate: one row per (customer_unique_id, order) with timestamp
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
    WHERE prev_order_timestamp IS NOT NULL  -- skip first order (no prior)
),
customer_cadence AS (
    SELECT
        og.customer_unique_id,
        COUNT(*) + 1                            AS order_count,  -- +1 for the first order excluded above
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


-- ---------------------------------------------------------------------------
-- Q5. Bonus: Delivery Performance vs. Customer Satisfaction
-- ---------------------------------------------------------------------------
-- Compares estimated vs. actual delivery dates, buckets the outcome as
-- Early / On-Time / Late, and cross-references with review scores to
-- quantify the satisfaction cost of late deliveries.
--
-- Delivery delta = actual − estimated (in days):
--   Negative = delivered early
--   0        = on time
--   Positive = delivered late
--
-- Only includes delivered orders (order_status = 'delivered') with non-null
-- delivery dates.

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
