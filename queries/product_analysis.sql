SELECT 
    YEAR(order_date) AS order_year, 
    MONTH(order_date) AS order_month, 
    SUM(sales_amount) AS total_sales,
    COUNT(DISTINCT customer_key) AS total_customers
FROM [DGED_S481821].[DBO].[GOLD.FACT_SALES]
WHERE order_date IS NOT NULL
GROUP BY YEAR(order_date), MONTH(order_date)
ORDER BY YEAR(order_date), MONTH(order_date);

-- Alternative method using DATE truncation
SELECT 
    DATETRUNC(MONTH, order_date) AS order_date, 
    SUM(sales_amount) AS total_sales,
    COUNT(DISTINCT customer_key) AS total_customers
FROM [DGED_S481821].[DBO].[GOLD.FACT_SALES]
WHERE order_date IS NOT NULL
GROUP BY DATETRUNC(MONTH, order_date)
ORDER BY DATETRUNC(MONTH, order_date);

-- FORMAT function produces strings; be cautious with sorting
SELECT 
    FORMAT(order_date, 'yyyy-MMM') AS order_date, 
    SUM(sales_amount) AS total_sales,
    COUNT(DISTINCT customer_key) AS total_customers
FROM [DGED_S481821].[DBO].[GOLD.FACT_SALES]
WHERE order_date IS NOT NULL
GROUP BY FORMAT(order_date, 'yyyy-MMM')
ORDER BY FORMAT(order_date, 'yyyy-MMM');

-- Total sales for each month with a running total over time
SELECT
    order_year,
    order_month,
    total_sales,
    SUM(total_sales) OVER (PARTITION BY order_year ORDER BY order_year, order_month) AS running_total_sales
FROM 
(
    SELECT
        DATEPART(YEAR, order_date) AS order_year, 
        DATEPART(MONTH, order_date) AS order_month, 
        SUM(sales_amount) AS total_sales 
    FROM [DGED_S481821].[DBO].[GOLD.FACT_SALES]
    WHERE order_date IS NOT NULL
    GROUP BY DATEPART(YEAR, order_date), DATEPART(MONTH, order_date)
) AS t
ORDER BY order_year, order_month;

-- Performance analysis: Compare product sales to average and previous year
WITH yearly_product_sales AS (
    SELECT 
        DATEPART(YEAR, order_date) AS current_year, 
        p.product_name, 
        SUM(f.sales_amount) AS total_sales
    FROM [DGED_S481821].[DBO].[GOLD.FACT_SALES] f
    LEFT JOIN [DGED_S481821].[DBO].[DGED_S481821].[DBO].[GOLD.DIM_PRODUCTS] p
        ON f.product_key = p.product_key
    WHERE order_date IS NOT NULL
    GROUP BY DATEPART(YEAR, order_date), p.product_name
)
SELECT
    current_year,
    product_name,
    total_sales,
    AVG(total_sales) OVER(PARTITION BY product_name) AS avg_product_sales, 
    total_sales - AVG(total_sales) OVER(PARTITION BY product_name) AS diff_from_avg, 
    CASE 
        WHEN total_sales - AVG(total_sales) OVER(PARTITION BY product_name) > 0 THEN 'ABOVE AVG'
        WHEN total_sales - AVG(total_sales) OVER(PARTITION BY product_name) < 0 THEN 'BELOW AVG'
        ELSE 'NO CHANGE'
    END AS avg_change,
    LAG(total_sales) OVER(PARTITION BY product_name ORDER BY current_year) AS prev_sales,
    total_sales - LAG(total_sales) OVER(PARTITION BY product_name ORDER BY current_year) AS diff_from_prev,
    CASE 
        WHEN total_sales - LAG(total_sales) OVER(PARTITION BY product_name ORDER BY current_year) > 0 THEN 'INCREASE'
        WHEN total_sales - LAG(total_sales) OVER(PARTITION BY product_name ORDER BY current_year) < 0 THEN 'DECREASE'
        ELSE 'NO CHANGE'
    END AS prev_change
FROM yearly_product_sales
ORDER BY product_name, current_year;

-- Part-to-whole analysis: Sales distribution by category
WITH category_sales AS (
    SELECT 
        category,
        SUM(sales_amount) AS total_sales
    FROM [DGED_S481821].[DBO].[GOLD.FACT_SALES] f
    LEFT JOIN [DGED_S481821].[DBO].[DGED_S481821].[DBO].[GOLD.DIM_PRODUCTS] p
        ON f.product_key = p.product_key
    GROUP BY category
)
SELECT 
    category,
    total_sales,
    CONCAT(ROUND((CAST(total_sales AS FLOAT) / SUM(total_sales) OVER()) * 100,2), '%') AS percentage_of_total
FROM category_sales
ORDER BY total_sales DESC;

-- Data segmentation: Classify products by cost range
WITH products_cte AS (
    SELECT
        product_key,
        product_name,
        cost,
        CASE 
            WHEN cost < 500 THEN 'BELOW 500'
            WHEN cost BETWEEN 500 AND 1000 THEN '500-1000'
            ELSE '1000+'
        END AS cost_range
    FROM [DGED_S481821].[DBO].[GOLD.DIM_PRODUCTS]
)
SELECT 
    cost_range,
    COUNT(product_key) AS total_products
FROM products_cte
GROUP BY cost_range;

-- Classify customers into VIP, Regular, and New based on spending and duration
WITH client_cte AS (
    SELECT
        c.customer_key,
        SUM(f.sales_amount) AS total_spending,
        MIN(order_date) AS first_order,
        MAX(order_date) AS last_order,
        CASE 
            WHEN DATEDIFF(YEAR, MIN(order_date), MAX(order_date)) < 1 THEN 'LESS THAN 1 YEAR'
            ELSE '1 YEAR+'
        END AS years_being_client,
        CASE 
            WHEN SUM(f.sales_amount) < 5000 THEN 'LOW SPENDER'
            ELSE 'HIGH SPENDER'
        END AS type_of_spenders
    FROM [GOLD.DIM_CUSTOMERS] c 
    LEFT JOIN [GOLD.FACT_SALES] f 
        ON f.customer_key = c.customer_key
    GROUP BY c.customer_key
)
SELECT
    type_of_customer AS customer_category, 
    COUNT(customer_key) AS count_of_customer_types
FROM (
    SELECT 
        customer_key,
        CASE 
            WHEN type_of_spenders = 'HIGH SPENDER' AND years_being_client = '1 YEAR+' THEN 'VIP'
            WHEN type_of_spenders = 'LOW SPENDER' AND years_being_client = '1 YEAR+' THEN 'REGULAR'
            ELSE 'NEW'
        END AS type_of_customer
    FROM client_cte
) t
GROUP BY type_of_customer;
