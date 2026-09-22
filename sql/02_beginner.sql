-- Q1. Total Revenue
SELECT
    ROUND(SUM(payment_value), 2) AS total_revenue
FROM olist.order_payments;


-- Q2. Total Order Count
SELECT
    COUNT(DISTINCT order_id) AS total_orders
FROM olist.orders;


-- Q3. Top 10 Best-Selling Products (by quantity sold)
SELECT
    product_id,
    COUNT(*)        AS units_sold,
    ROUND(SUM(price), 2) AS total_product_revenue
FROM olist.order_items
GROUP BY product_id
ORDER BY units_sold DESC
LIMIT 10;


-- Q4. Orders per Customer State
SELECT
    c.customer_state,
    COUNT(o.order_id) AS order_count
FROM olist.orders o
JOIN olist.customers c ON o.customer_id = c.customer_id
GROUP BY c.customer_state
ORDER BY order_count DESC;


-- Q5. Average Review Score (overall)
SELECT
    ROUND(AVG(review_score), 2) AS avg_review_score,
    COUNT(*)                     AS total_reviews
FROM olist.order_reviews;


-- Q6. WHERE Filtering — Orders in a Specific Date Range
SELECT
    order_id,
    order_purchase_timestamp,
    order_status
FROM olist.orders
WHERE order_purchase_timestamp >= '2018-01-01'
  AND order_purchase_timestamp <  '2018-04-01'
ORDER BY order_purchase_timestamp
LIMIT 20;


-- Q7. WHERE Filtering — Orders by Status
SELECT
    order_status,
    COUNT(*) AS order_count
FROM olist.orders
GROUP BY order_status
ORDER BY order_count DESC;


-- Q8. LIKE Pattern Matching — Product Categories Containing 'moveis'
SELECT DISTINCT
    product_category_name
FROM olist.products
WHERE product_category_name ILIKE '%moveis%'
ORDER BY product_category_name;


-- Q9. ORDER BY + LIMIT — Top 5 Highest Single-Payment Transactions
SELECT
    order_id,
    payment_type,
    payment_installments,
    payment_value
FROM olist.order_payments
ORDER BY payment_value DESC
LIMIT 5;


-- Q10. Full Aggregate Set with GROUP BY — Per-State Revenue Summary
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


-- Q11. Monthly Order Trend
SELECT
    DATE_TRUNC('month', order_purchase_timestamp)::DATE AS order_month,
    COUNT(*)                                             AS order_count
FROM olist.orders
GROUP BY DATE_TRUNC('month', order_purchase_timestamp)
ORDER BY order_month;


-- Q12. Review Score Distribution
-- pct_of_total uses a window function, not a second query
SELECT
    review_score,
    COUNT(*)                                       AS review_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS pct_of_total
FROM olist.order_reviews
GROUP BY review_score
ORDER BY review_score;
