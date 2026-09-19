-- =============================================================================
-- Olist E-Commerce Analytics — Phase 2: Beginner SQL
-- =============================================================================
-- Demonstrates SQL fundamentals: aggregates, filtering, sorting, grouping.
-- Minimal joins — only where unavoidable (e.g. orders → customers for state).
--
-- Run: psql -U postgres -d olist_ecommerce -f sql/02_beginner.sql
-- =============================================================================


-- ---------------------------------------------------------------------------
-- Q1. Total Revenue
-- ---------------------------------------------------------------------------
-- Revenue = sum of all payment values across all orders.
-- Uses order_payments because that's where monetary amounts live.
-- (order_items.price is per-item; payments capture the actual charged total
-- including freight, installment fees, etc.)

SELECT
    ROUND(SUM(payment_value), 2) AS total_revenue
FROM olist.order_payments;


-- ---------------------------------------------------------------------------
-- Q2. Total Order Count
-- ---------------------------------------------------------------------------
-- COUNT DISTINCT on order_id from the orders table (the authoritative
-- source for order-level facts).

SELECT
    COUNT(DISTINCT order_id) AS total_orders
FROM olist.orders;


-- ---------------------------------------------------------------------------
-- Q3. Top 10 Best-Selling Products (by quantity sold)
-- ---------------------------------------------------------------------------
-- Each row in order_items represents one unit sold (order_item_id is the
-- sequence within that order). COUNT(*) grouped by product_id gives units.

SELECT
    product_id,
    COUNT(*)        AS units_sold,
    ROUND(SUM(price), 2) AS total_product_revenue
FROM olist.order_items
GROUP BY product_id
ORDER BY units_sold DESC
LIMIT 10;


-- ---------------------------------------------------------------------------
-- Q4. Orders per Customer State
-- ---------------------------------------------------------------------------
-- Requires one simple join: orders → customers (to get state).
-- This is the only join in this file.

SELECT
    c.customer_state,
    COUNT(o.order_id) AS order_count
FROM olist.orders o
JOIN olist.customers c ON o.customer_id = c.customer_id
GROUP BY c.customer_state
ORDER BY order_count DESC;


-- ---------------------------------------------------------------------------
-- Q5. Average Review Score (overall)
-- ---------------------------------------------------------------------------

SELECT
    ROUND(AVG(review_score), 2) AS avg_review_score,
    COUNT(*)                     AS total_reviews
FROM olist.order_reviews;


-- ---------------------------------------------------------------------------
-- Q6. WHERE Filtering — Orders in a Specific Date Range
-- ---------------------------------------------------------------------------
-- Orders placed in 2018 Q1 (Jan–Mar 2018), showing how WHERE narrows results.

SELECT
    order_id,
    order_purchase_timestamp,
    order_status
FROM olist.orders
WHERE order_purchase_timestamp >= '2018-01-01'
  AND order_purchase_timestamp <  '2018-04-01'
ORDER BY order_purchase_timestamp
LIMIT 20;


-- ---------------------------------------------------------------------------
-- Q7. WHERE Filtering — Orders by Status
-- ---------------------------------------------------------------------------
-- Count orders by status to see the distribution (delivered, shipped,
-- canceled, etc.).

SELECT
    order_status,
    COUNT(*) AS order_count
FROM olist.orders
GROUP BY order_status
ORDER BY order_count DESC;


-- ---------------------------------------------------------------------------
-- Q8. LIKE Pattern Matching — Product Categories Containing 'moveis'
-- ---------------------------------------------------------------------------
-- Portuguese product categories that contain the word 'moveis' (furniture).
-- Demonstrates case-insensitive pattern matching with ILIKE.

SELECT DISTINCT
    product_category_name
FROM olist.products
WHERE product_category_name ILIKE '%moveis%'
ORDER BY product_category_name;


-- ---------------------------------------------------------------------------
-- Q9. ORDER BY + LIMIT — Top 5 Highest Single-Payment Transactions
-- ---------------------------------------------------------------------------
-- The single largest payment_value entries across all orders.

SELECT
    order_id,
    payment_type,
    payment_installments,
    payment_value
FROM olist.order_payments
ORDER BY payment_value DESC
LIMIT 5;


-- ---------------------------------------------------------------------------
-- Q10. Full Aggregate Set with GROUP BY — Per-State Revenue Summary
-- ---------------------------------------------------------------------------
-- Demonstrates COUNT, SUM, AVG, MIN, MAX all in one query.
-- Groups by customer_state (requires the orders → customers join).

SELECT
    c.customer_state,
    COUNT(DISTINCT o.order_id)        AS total_orders,
    ROUND(SUM(p.payment_value), 2)    AS total_revenue,
    ROUND(AVG(p.payment_value), 2)    AS avg_payment,
    ROUND(MIN(p.payment_value), 2)    AS min_payment,
    ROUND(MAX(p.payment_value), 2)    AS max_payment
FROM olist.orders o
JOIN olist.customers c      ON o.customer_id = c.customer_id
JOIN olist.order_payments p ON o.order_id    = p.order_id
GROUP BY c.customer_state
ORDER BY total_revenue DESC;


-- ---------------------------------------------------------------------------
-- Q11. Monthly Order Trend
-- ---------------------------------------------------------------------------
-- Bonus: shows DATE_TRUNC for grouping by month — a preview of what's
-- used heavily in Phase 4's cohort analysis.

SELECT
    DATE_TRUNC('month', order_purchase_timestamp)::DATE AS order_month,
    COUNT(*)                                             AS order_count
FROM olist.orders
GROUP BY DATE_TRUNC('month', order_purchase_timestamp)
ORDER BY order_month;


-- ---------------------------------------------------------------------------
-- Q12. Review Score Distribution
-- ---------------------------------------------------------------------------
-- How many reviews at each score level (1–5)?

SELECT
    review_score,
    COUNT(*)                                       AS review_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS pct_of_total
FROM olist.order_reviews
GROUP BY review_score
ORDER BY review_score;
