-- 1) Base Query: Retrieves core columns from tables
WITH base_query AS (
    SELECT 
        f.order_number, 
        f.product_key,  
        f.order_date, 
        f.sales_amount,  
        f.quantity,  
        c.customer_key, 
        c.customer_number,  
        CONCAT(c.last_name, ' ', c.first_name) AS customer_name,  -- Full name of the customer
        DATEDIFF(YEAR, c.birthdate, GETDATE()) AS age  -- Calculates customer age based on birthdate
    FROM [gold.fact_sales] f
    LEFT JOIN [gold.dim_customers] c
        ON c.customer_key = f.customer_key 
    WHERE order_date IS NOT NULL  -- Exclude records with null order dates
),

-- 2) Customer Aggregations: Summarizes key metrics at the customer level
CUSTOMER_AGGREGATION AS (
    SELECT 
        customer_key,
        customer_number,
        customer_name,
        age,
        COUNT(DISTINCT order_number) AS total_orders,  -- Total number of unique orders placed by the customer
        SUM(sales_amount) AS total_sales,  -- Total revenue generated from the customer
        SUM(quantity) AS total_quantity_of_bought_items,  -- Total number of items purchased
        COUNT(DISTINCT product_key) AS total_diff_products,  -- Number of unique products purchased
        MAX(order_date) AS last_order,  -- Date of the most recent order
        DATEDIFF(MONTH, MIN(order_date), MAX(order_date)) AS lifespan  -- Number of months between first and last order
    FROM base_query
    GROUP BY customer_key, customer_number, customer_name, age
)
SELECT
    customer_key,
    customer_number,
    customer_name,
    age,
    -- Categorizing customers based on age
    CASE 
        WHEN age < 20 THEN 'Under 20'
        WHEN age BETWEEN 20 AND 29 THEN '20-29'
        WHEN age BETWEEN 30 AND 39 THEN '30-39'
        WHEN age BETWEEN 40 AND 49 THEN '40-49'
        ELSE '50+'
    END AS type_of_customer,
    -- Categorizing customers based on their purchasing history
    CASE 
        WHEN lifespan >= 1 AND total_sales > 5000 THEN 'VIP'
        WHEN lifespan >= 1 AND total_sales <= 5000 THEN 'Regular'
        ELSE 'New'
    END AS customer_category,
    DATEDIFF(MONTH, last_order, GETDATE()) AS recency,  -- Number of months since the last order
    -- Calculate average order value (total sales divided by total orders)
    CASE 
        WHEN total_orders = 0 THEN 0
        ELSE (total_sales / total_orders) 
    END AS avg_order_value,
    total_orders,  
    total_sales,  
    total_quantity_of_bought_items, 
    total_diff_products,  
    -- Compute average monthly spend
    CASE 
        WHEN lifespan = 0 THEN total_sales
        ELSE total_sales / lifespan
    END AS avg_monthly_spend,
    lifespan  -- Customer's purchasing activity duration in months
FROM customer_aggregation;
