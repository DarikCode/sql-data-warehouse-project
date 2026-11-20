/*
=============================================================
 Quality checks: gold layer
=============================================================
 Purpose:
   Proves the star schema is correct and safe to report on:
   - every key is unique
   - joins did not duplicate or lose any rows
   - every sale connects to a customer and a product
   - totals match silver exactly
   Every failed_rows count must be 0.

   If any check fails, the script raises an error, so a
   script or CI job running it will stop and report FAILED.

 How to run:
   psql -U postgres -h localhost -d datawarehouse -v ON_ERROR_STOP=1 -f tests/quality_checks_gold.sql
=============================================================
*/

-- A temporary table disappears automatically when the session ends.
CREATE TEMP TABLE gold_checks AS
-- ---------- dim_customers ----------
SELECT 'dim_customers: customer_key is not unique' AS check_name,
       COUNT(*) AS failed_rows
FROM (SELECT customer_key FROM gold.dim_customers GROUP BY 1 HAVING COUNT(*) > 1) d
UNION ALL
-- If an ERP table had two rows for one customer, the LEFT JOIN
-- would silently create a duplicate customer. This catches it.
SELECT 'dim_customers: row count differs from silver customers',
       ABS((SELECT COUNT(*) FROM gold.dim_customers) - (SELECT COUNT(*) FROM silver.crm_cust_info))
UNION ALL
SELECT 'dim_customers: unexpected gender value',
       COUNT(*) FROM gold.dim_customers WHERE gender NOT IN ('Female', 'Male', 'n/a')

-- ---------- dim_products ----------
UNION ALL
SELECT 'dim_products: product_key is not unique',
       COUNT(*) FROM (SELECT product_key FROM gold.dim_products GROUP BY 1 HAVING COUNT(*) > 1) d
UNION ALL
-- The fact table joins on product_number, so it must be unique,
-- or one sale would turn into several.
SELECT 'dim_products: product_number is not unique',
       COUNT(*) FROM (SELECT product_number FROM gold.dim_products GROUP BY 1 HAVING COUNT(*) > 1) d

-- ---------- fact_sales ----------
UNION ALL
SELECT 'fact_sales: row count differs from silver sales',
       ABS((SELECT COUNT(*) FROM gold.fact_sales) - (SELECT COUNT(*) FROM silver.crm_sales_details))
UNION ALL
SELECT 'fact_sales: total sales amount differs from silver',
       CASE WHEN (SELECT SUM(sales_amount) FROM gold.fact_sales)
               = (SELECT SUM(sls_sales) FROM silver.crm_sales_details)
            THEN 0 ELSE 1 END
UNION ALL
SELECT 'fact_sales: sale has no matching customer',
       COUNT(*) FROM gold.fact_sales f
       WHERE NOT EXISTS (SELECT 1 FROM gold.dim_customers c WHERE c.customer_key = f.customer_key)
UNION ALL
SELECT 'fact_sales: sale has no matching product',
       COUNT(*) FROM gold.fact_sales f
       WHERE NOT EXISTS (SELECT 1 FROM gold.dim_products p WHERE p.product_key = f.product_key);

-- Show the results
SELECT check_name,
       failed_rows,
       CASE WHEN failed_rows = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM gold_checks
ORDER BY check_name;

-- Stop with an error if anything failed
DO $$
DECLARE
    v_failed INT;
BEGIN
    SELECT COUNT(*) INTO v_failed FROM gold_checks WHERE failed_rows > 0;
    IF v_failed > 0 THEN
        RAISE EXCEPTION '% gold quality check(s) FAILED', v_failed;
    END IF;
    RAISE NOTICE 'All gold quality checks passed';
END;
$$;
