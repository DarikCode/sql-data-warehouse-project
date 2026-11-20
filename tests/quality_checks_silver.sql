/*
=============================================================
 Quality checks: silver layer
=============================================================
 Purpose:
   Proves the silver load fixed the problems found during
   profiling. Each check counts the rows that break a rule;
   every count must be 0.

   If any check fails, the script raises an error, so a
   script or CI job running it will stop and report FAILED.

 How to run (after CALL silver.load_silver();):
   psql -U postgres -h localhost -d datawarehouse -v ON_ERROR_STOP=1 -f tests/quality_checks_silver.sql
=============================================================
*/

-- A temporary table disappears automatically when the session ends.
CREATE TEMP TABLE silver_checks AS
-- ---------- crm_cust_info ----------
SELECT 'crm_cust_info: customer ID is missing' AS check_name,
       COUNT(*) AS failed_rows
FROM silver.crm_cust_info WHERE cst_id IS NULL
UNION ALL
SELECT 'crm_cust_info: customer ID is duplicated',
       COUNT(*) FROM (SELECT cst_id FROM silver.crm_cust_info GROUP BY cst_id HAVING COUNT(*) > 1) d
UNION ALL
SELECT 'crm_cust_info: name has extra spaces',
       COUNT(*) FROM silver.crm_cust_info
       WHERE cst_firstname <> TRIM(cst_firstname) OR cst_lastname <> TRIM(cst_lastname)
UNION ALL
SELECT 'crm_cust_info: unexpected marital status / gender value',
       COUNT(*) FROM silver.crm_cust_info
       WHERE cst_marital_status NOT IN ('Single', 'Married', 'n/a')
          OR cst_gndr NOT IN ('Female', 'Male', 'n/a')

-- ---------- crm_prd_info ----------
UNION ALL
SELECT 'crm_prd_info: product ID is missing or duplicated',
       COUNT(*) FROM (SELECT prd_id FROM silver.crm_prd_info GROUP BY prd_id
                      HAVING COUNT(*) > 1 OR prd_id IS NULL) d
UNION ALL
SELECT 'crm_prd_info: cost is missing or negative',
       COUNT(*) FROM silver.crm_prd_info WHERE prd_cost IS NULL OR prd_cost < 0
UNION ALL
SELECT 'crm_prd_info: end date before start date',
       COUNT(*) FROM silver.crm_prd_info WHERE prd_end_dt < prd_start_dt
UNION ALL
SELECT 'crm_prd_info: product has more than one current version',
       COUNT(*) FROM (SELECT prd_key FROM silver.crm_prd_info WHERE prd_end_dt IS NULL
                      GROUP BY prd_key HAVING COUNT(*) > 1) d
UNION ALL
SELECT 'crm_prd_info: category ID not found in ERP categories',
       COUNT(*) FROM silver.crm_prd_info p
       WHERE NOT EXISTS (SELECT 1 FROM silver.erp_px_cat_g1v2 c WHERE c.id = p.cat_id)
         AND p.cat_id <> 'CO_PE'  -- known: 'CO_PE' (pedals) has no category in the ERP

-- ---------- crm_sales_details ----------
UNION ALL
SELECT 'crm_sales_details: order date after ship or due date',
       COUNT(*) FROM silver.crm_sales_details
       WHERE sls_order_dt > sls_ship_dt OR sls_order_dt > sls_due_dt
UNION ALL
SELECT 'crm_sales_details: sales, quantity or price missing / not positive',
       COUNT(*) FROM silver.crm_sales_details
       WHERE sls_sales IS NULL OR sls_quantity IS NULL OR sls_price IS NULL
          OR sls_sales <= 0 OR sls_quantity <= 0 OR sls_price <= 0
UNION ALL
SELECT 'crm_sales_details: sales <> quantity x price',
       COUNT(*) FROM silver.crm_sales_details WHERE sls_sales <> sls_quantity * sls_price
UNION ALL
SELECT 'crm_sales_details: product not found in products',
       COUNT(*) FROM silver.crm_sales_details s
       WHERE NOT EXISTS (SELECT 1 FROM silver.crm_prd_info p WHERE p.prd_key = s.sls_prd_key)
UNION ALL
SELECT 'crm_sales_details: customer not found in customers',
       COUNT(*) FROM silver.crm_sales_details s
       WHERE NOT EXISTS (SELECT 1 FROM silver.crm_cust_info c WHERE c.cst_id = s.sls_cust_id)

-- ---------- erp_cust_az12 ----------
UNION ALL
SELECT 'erp_cust_az12: birthdate in the future',
       COUNT(*) FROM silver.erp_cust_az12 WHERE bdate > CURRENT_DATE
UNION ALL
SELECT 'erp_cust_az12: unexpected gender value',
       COUNT(*) FROM silver.erp_cust_az12 WHERE gen NOT IN ('Female', 'Male', 'n/a')
UNION ALL
SELECT 'erp_cust_az12: ID does not match any CRM customer key',
       COUNT(*) FROM silver.erp_cust_az12 e
       WHERE NOT EXISTS (SELECT 1 FROM silver.crm_cust_info c WHERE c.cst_key = e.cid)

-- ---------- erp_loc_a101 ----------
UNION ALL
SELECT 'erp_loc_a101: country is blank, abbreviated or untrimmed',
       COUNT(*) FROM silver.erp_loc_a101
       WHERE cntry IS NULL OR cntry <> TRIM(cntry) OR cntry IN ('', 'DE', 'US', 'USA')
UNION ALL
SELECT 'erp_loc_a101: ID does not match any CRM customer key',
       COUNT(*) FROM silver.erp_loc_a101 e
       WHERE NOT EXISTS (SELECT 1 FROM silver.crm_cust_info c WHERE c.cst_key = e.cid);

-- Show the results
SELECT check_name,
       failed_rows,
       CASE WHEN failed_rows = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM silver_checks
ORDER BY check_name;

-- Stop with an error if anything failed
DO $$
DECLARE
    v_failed INT;
BEGIN
    SELECT COUNT(*) INTO v_failed FROM silver_checks WHERE failed_rows > 0;
    IF v_failed > 0 THEN
        RAISE EXCEPTION '% silver quality check(s) FAILED', v_failed;
    END IF;
    RAISE NOTICE 'All silver quality checks passed';
END;
$$;
