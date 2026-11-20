/*
=============================================================
 Business questions answered from the gold layer
=============================================================
 Purpose:
   Shows what the warehouse is for. Each question below
   needed data from BOTH source systems (CRM + ERP), which
   was impractical before the warehouse existed. With the
   star schema, each one is a short query.

 How to run:
   psql -U postgres -h localhost -d datawarehouse -f analysis/02_business_questions.sql
=============================================================
*/

\echo ''
\echo 'Q1. How did revenue develop per year?'
\echo '    (2010 and 2014 contain only a few weeks of data)'
SELECT
    EXTRACT(YEAR FROM order_date)::int  AS order_year,
    SUM(sales_amount)                   AS revenue,
    COUNT(DISTINCT customer_key)        AS customers,
    SUM(quantity)                       AS items_sold
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY order_year
ORDER BY order_year;

\echo ''
\echo 'Q2. Which product categories bring in the revenue?'
SELECT
    p.category,
    SUM(f.sales_amount)                                             AS revenue,
    ROUND(100.0 * SUM(f.sales_amount) / SUM(SUM(f.sales_amount)) OVER (), 1) AS pct_of_total
FROM gold.fact_sales f
JOIN gold.dim_products p ON p.product_key = f.product_key
GROUP BY p.category
ORDER BY revenue DESC;

\echo ''
\echo 'Q3. Which countries buy the most mountain bikes, and how old are those buyers?'
\echo '    (country and birthdate come from the ERP, sales from the CRM)'
SELECT
    c.country,
    SUM(f.sales_amount)                                                 AS revenue,
    COUNT(DISTINCT f.customer_key)                                      AS customers,
    ROUND(AVG(EXTRACT(YEAR FROM age(f.order_date, c.birthdate))))::int  AS avg_age_at_purchase
FROM gold.fact_sales f
JOIN gold.dim_customers c ON c.customer_key = f.customer_key
JOIN gold.dim_products  p ON p.product_key  = f.product_key
WHERE p.subcategory = 'Mountain Bikes'
GROUP BY c.country
ORDER BY revenue DESC;

\echo ''
\echo 'Q4. Which age groups spend the most per customer?'
WITH customer_spend AS (
    SELECT
        c.customer_key,
        EXTRACT(YEAR FROM age(MIN(f.order_date), c.birthdate))::int AS age_at_first_order,
        SUM(f.sales_amount)                                          AS total_spent
    FROM gold.fact_sales f
    JOIN gold.dim_customers c ON c.customer_key = f.customer_key
    WHERE c.birthdate IS NOT NULL
    GROUP BY c.customer_key, c.birthdate
)
SELECT
    CASE
        WHEN age_at_first_order < 30 THEN '1) under 30'
        WHEN age_at_first_order < 40 THEN '2) 30-39'
        WHEN age_at_first_order < 50 THEN '3) 40-49'
        WHEN age_at_first_order < 60 THEN '4) 50-59'
        ELSE                              '5) 60+'
    END                              AS age_group,
    COUNT(*)                         AS customers,
    SUM(total_spent)                 AS revenue,
    ROUND(AVG(total_spent))::int     AS avg_spent_per_customer
FROM customer_spend
GROUP BY age_group
ORDER BY age_group;
