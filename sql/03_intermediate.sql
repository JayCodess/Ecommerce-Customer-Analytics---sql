-- Q1. Multi-Table JOIN — Full Order Details with English Category Names
-- LEFT JOIN on reviews/translation — not every order has one
SELECT
    o.order_id,
    o.order_purchase_timestamp,
    o.order_status,
    c.customer_unique_id,
    c.customer_state,
    oi.order_item_id,
    p.product_id,
    COALESCE(t.product_category_name_english, p.product_category_name, 'unknown')
        AS product_category_english,
    oi.price,
    oi.freight_value,
    r.review_score
FROM olist.orders o
JOIN      olist.customers                  c ON o.customer_id          = c.customer_id
JOIN      olist.order_items               oi ON o.order_id             = oi.order_id
JOIN      olist.products                   p ON oi.product_id          = p.product_id
LEFT JOIN olist.product_category_translation t ON p.product_category_name = t.product_category_name
LEFT JOIN olist.order_reviews              r ON o.order_id             = r.order_id
ORDER BY o.order_purchase_timestamp DESC
LIMIT 20;


-- Q2. GROUP BY + HAVING — Underperforming Sellers (50+ orders, avg rating < 3)
SELECT
    oi.seller_id,
    COUNT(DISTINCT o.order_id)    AS total_orders,
    COUNT(*)                      AS items_sold,
    ROUND(AVG(r.review_score), 2) AS avg_review_score,
    ROUND(SUM(oi.price), 2)       AS total_revenue
FROM olist.order_items oi
JOIN olist.orders        o ON oi.order_id = o.order_id
JOIN olist.order_reviews r ON o.order_id  = r.order_id
GROUP BY oi.seller_id
HAVING COUNT(*) >= 50
   AND AVG(r.review_score) < 3
ORDER BY avg_review_score ASC, items_sold DESC;


-- Q3. Subquery — Customers Who Spent More Than the Overall Average
-- CTE computes spend once, reused for both the row and the average
WITH customer_spend AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS order_count,
        ROUND(SUM(p.payment_value), 2) AS lifetime_spend
    FROM olist.customers c
    JOIN olist.orders         o ON c.customer_id = o.customer_id
    JOIN olist.order_payments p ON o.order_id    = p.order_id
    GROUP BY c.customer_unique_id
)
SELECT
    customer_unique_id,
    order_count,
    lifetime_spend
FROM customer_spend
WHERE lifetime_spend > (SELECT AVG(lifetime_spend) FROM customer_spend)
ORDER BY lifetime_spend DESC
LIMIT 20;


-- Q4. CASE Bucketing — Order Value Tiers
WITH order_totals AS (
    SELECT
        o.order_id,
        SUM(p.payment_value) AS order_value
    FROM olist.orders o
    JOIN olist.order_payments p ON o.order_id = p.order_id
    GROUP BY o.order_id
),
order_tiers AS (
    SELECT
        ot.order_id,
        ot.order_value,
        CASE
            WHEN ot.order_value < 50   THEN 'Low (<R$50)'
            WHEN ot.order_value < 200  THEN 'Medium (R$50–200)'
            WHEN ot.order_value < 500  THEN 'High (R$200–500)'
            ELSE                            'Premium (>R$500)'
        END AS value_tier
    FROM order_totals ot
)
SELECT
    vt.value_tier,
    COUNT(*)                       AS order_count,
    ROUND(AVG(vt.order_value), 2)  AS avg_order_value,
    ROUND(AVG(r.review_score), 2)  AS avg_review_score
FROM order_tiers vt
LEFT JOIN olist.order_reviews r ON vt.order_id = r.order_id
GROUP BY vt.value_tier
ORDER BY
    CASE vt.value_tier
        WHEN 'Low (<R$50)'        THEN 1
        WHEN 'Medium (R$50–200)'  THEN 2
        WHEN 'High (R$200–500)'   THEN 3
        WHEN 'Premium (>R$500)'   THEN 4
    END;


-- Q5. Composition Query — Seller Performance Dashboard
-- aggregating at seller level avoids the order-item fan-out from the review join
WITH seller_metrics AS (
    SELECT
        s.seller_id,
        s.seller_city,
        s.seller_state,
        COUNT(*)                        AS items_sold,
        COUNT(DISTINCT o.order_id)      AS distinct_orders,
        COUNT(DISTINCT c.customer_unique_id) AS unique_customers,
        ROUND(SUM(oi.price), 2)         AS total_revenue,
        ROUND(AVG(r.review_score), 2)   AS avg_review,
        ROUND(AVG(
            EXTRACT(DAY FROM (o.order_delivered_customer_date
                              - o.order_estimated_delivery_date))
        ), 1)                           AS avg_delivery_delta_days
    FROM olist.order_items oi
    JOIN      olist.orders    o ON oi.order_id   = o.order_id
    JOIN      olist.sellers   s ON oi.seller_id  = s.seller_id
    JOIN      olist.customers c ON o.customer_id = c.customer_id
    LEFT JOIN olist.order_reviews r ON o.order_id = r.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY s.seller_id, s.seller_city, s.seller_state
    HAVING COUNT(*) >= 30
),
platform_avg AS (
    SELECT
        ROUND(AVG(avg_review), 2)              AS global_avg_review,
        ROUND(AVG(avg_delivery_delta_days), 1) AS global_avg_delta
    FROM seller_metrics
)
SELECT
    sm.seller_id,
    sm.seller_city,
    sm.seller_state,
    sm.items_sold,
    sm.distinct_orders,
    sm.unique_customers,
    sm.total_revenue,
    sm.avg_review,
    sm.avg_delivery_delta_days,
    pa.global_avg_review,
    pa.global_avg_delta,
    CASE
        WHEN sm.avg_review >= 4.0
         AND sm.avg_delivery_delta_days < 0
            THEN '★ Star Seller'
        WHEN sm.avg_review >= pa.global_avg_review
         AND sm.avg_delivery_delta_days <= pa.global_avg_delta
            THEN '● Above Average'
        WHEN sm.avg_review < 3.0
          OR sm.avg_delivery_delta_days > 10
            THEN '▼ Underperformer'
        ELSE '■ Average'
    END AS performance_tier
FROM seller_metrics sm
CROSS JOIN platform_avg pa
ORDER BY sm.total_revenue DESC;
