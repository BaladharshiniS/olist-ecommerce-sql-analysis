-- Olist Brazilian E-Commerce: SQL analysis (SQLite)
-- Scope: delivered orders placed Jan 2017 to Aug 2018
-- Revenue = SUM(order_items.price); freight is excluded

CREATE VIEW IF NOT EXISTS delivered_orders AS
SELECT * FROM orders
WHERE order_status = 'delivered';


-- Q1: Monthly revenue and orders
SELECT strftime('%Y-%m', o.order_purchase_timestamp) AS month,
       COUNT(DISTINCT o.order_id) AS orders,
       ROUND(SUM(oi.price), 2) AS revenue
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp >= '2017-01-01'
  AND o.order_purchase_timestamp <  '2018-09-01'
GROUP BY month
ORDER BY month;


-- Q2: Top 10 categories by revenue
SELECT COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS category,
       COUNT(DISTINCT oi.order_id) AS orders,
       ROUND(SUM(oi.price), 2) AS revenue,
       ROUND(100.0 * SUM(oi.price) / SUM(SUM(oi.price)) OVER (), 1) AS pct_of_revenue
FROM delivered_orders o
JOIN order_items oi ON o.order_id = oi.order_id
JOIN products p ON oi.product_id = p.product_id
LEFT JOIN category_translation t ON p.product_category_name = t.product_category_name
WHERE o.order_purchase_timestamp >= '2017-01-01'
  AND o.order_purchase_timestamp <  '2018-09-01'
GROUP BY category
ORDER BY revenue DESC
LIMIT 10;


-- Q3: Revenue by customer state
SELECT c.customer_state,
       COUNT(DISTINCT o.order_id) AS orders,
       ROUND(SUM(oi.price), 2) AS revenue,
       ROUND(100.0 * SUM(oi.price) / SUM(SUM(oi.price)) OVER (), 1) AS pct_of_revenue,
       ROUND(SUM(oi.price) / COUNT(DISTINCT o.order_id), 2) AS avg_order_value
FROM delivered_orders o
JOIN customers c ON o.customer_id = c.customer_id
JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.order_purchase_timestamp >= '2017-01-01'
  AND o.order_purchase_timestamp <  '2018-09-01'
GROUP BY c.customer_state
ORDER BY revenue DESC
LIMIT 10;


-- Q4: Payment methods
SELECT p.payment_type,
       COUNT(DISTINCT p.order_id) AS orders,
       ROUND(SUM(p.payment_value), 2) AS total_paid,
       ROUND(100.0 * SUM(p.payment_value) / SUM(SUM(p.payment_value)) OVER (), 1) AS pct_of_payments,
       ROUND(AVG(p.payment_installments), 1) AS avg_installments
FROM delivered_orders o
JOIN payments p ON o.order_id = p.order_id
WHERE o.order_purchase_timestamp >= '2017-01-01'
  AND o.order_purchase_timestamp <  '2018-09-01'
GROUP BY p.payment_type
ORDER BY total_paid DESC;


-- Q5: Delivery time and late deliveries by month
SELECT strftime('%Y-%m', order_purchase_timestamp) AS month,
       COUNT(*) AS delivered_orders,
       ROUND(AVG(julianday(order_delivered_customer_date)
               - julianday(order_purchase_timestamp)), 1) AS avg_delivery_days,
       ROUND(100.0 * SUM(CASE WHEN order_delivered_customer_date > order_estimated_delivery_date
                              THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_late
FROM delivered_orders
WHERE order_purchase_timestamp >= '2017-01-01'
  AND order_purchase_timestamp <  '2018-09-01'
  AND order_delivered_customer_date IS NOT NULL
  AND order_delivered_customer_date <> ''
GROUP BY month
ORDER BY month;


-- Q6: Late deliveries vs review scores
SELECT CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
            THEN 'Late' ELSE 'On time' END AS delivery_status,
       COUNT(*) AS reviews,
       ROUND(AVG(r.review_score), 2) AS avg_review_score,
       ROUND(100.0 * SUM(CASE WHEN r.review_score <= 2 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_low_scores
FROM delivered_orders o
JOIN reviews r ON o.order_id = r.order_id
WHERE o.order_purchase_timestamp >= '2017-01-01'
  AND o.order_purchase_timestamp <  '2018-09-01'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_delivered_customer_date <> ''
GROUP BY delivery_status;


-- Q7: Top 10 sellers by revenue
SELECT substr(oi.seller_id, 1, 8) AS seller,
       s.seller_state,
       COUNT(DISTINCT oi.order_id) AS orders,
       ROUND(SUM(oi.price), 2) AS revenue,
       ROUND(100.0 * SUM(oi.price) / SUM(SUM(oi.price)) OVER (), 2) AS pct_of_revenue
FROM delivered_orders o
JOIN order_items oi ON o.order_id = oi.order_id
JOIN sellers s ON oi.seller_id = s.seller_id
WHERE o.order_purchase_timestamp >= '2017-01-01'
  AND o.order_purchase_timestamp <  '2018-09-01'
GROUP BY oi.seller_id, s.seller_state
ORDER BY revenue DESC
LIMIT 10;


-- Q8: One-time vs repeat customers (CTE)
WITH customer_orders AS (
    SELECT c.customer_unique_id,
           COUNT(DISTINCT o.order_id) AS orders
    FROM delivered_orders o
    JOIN customers c ON o.customer_id = c.customer_id
    WHERE o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp <  '2018-09-01'
    GROUP BY c.customer_unique_id
)
SELECT CASE WHEN orders = 1 THEN '1 order'
            WHEN orders = 2 THEN '2 orders'
            ELSE '3+ orders' END AS customer_type,
       COUNT(*) AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_customers
FROM customer_orders
GROUP BY customer_type
ORDER BY customers DESC;


-- Q9: Month-over-month growth and running total (window functions)
WITH monthly AS (
    SELECT strftime('%Y-%m', o.order_purchase_timestamp) AS month,
           ROUND(SUM(oi.price), 2) AS revenue
    FROM delivered_orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp <  '2018-09-01'
    GROUP BY month
)
SELECT month,
       revenue,
       LAG(revenue) OVER (ORDER BY month) AS prev_month_revenue,
       ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY month))
             / LAG(revenue) OVER (ORDER BY month), 1) AS mom_growth_pct,
       ROUND(SUM(revenue) OVER (ORDER BY month), 2) AS running_total
FROM monthly
ORDER BY month;


-- Q10: Top category per state (CTEs + RANK window function)
WITH cat_state AS (
    SELECT c.customer_state AS state,
           COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS category,
           ROUND(SUM(oi.price), 2) AS revenue
    FROM delivered_orders o
    JOIN customers c ON o.customer_id = c.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    JOIN products p ON oi.product_id = p.product_id
    LEFT JOIN category_translation t ON p.product_category_name = t.product_category_name
    WHERE o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp <  '2018-09-01'
    GROUP BY state, category
),
ranked AS (
    SELECT state, category, revenue,
           RANK() OVER (PARTITION BY state ORDER BY revenue DESC) AS rnk,
           ROUND(100.0 * revenue / SUM(revenue) OVER (PARTITION BY state), 1) AS pct_of_state,
           ROUND(SUM(revenue) OVER (PARTITION BY state), 2) AS state_revenue
    FROM cat_state
)
SELECT state, category AS top_category, revenue, pct_of_state, state_revenue
FROM ranked
WHERE rnk = 1
ORDER BY state_revenue DESC
LIMIT 10;