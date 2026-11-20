/*
=============================================================
 Data profiling: find the problems in the bronze layer
=============================================================
 Purpose:
   Before writing any cleaning logic, measure what is actually
   wrong with the raw data. Every fix in the silver layer is
   based on a finding from this script.

 How to run:
   psql -U postgres -h localhost -d datawarehouse -f analysis/01_profile_bronze.sql
=============================================================
*/

\echo '########## crm_cust_info ##########'
SELECT
    COUNT(*)                                                    AS total_rows,
    COUNT(*) FILTER (WHERE cst_id IS NULL)                      AS missing_id,
    COUNT(*) - COUNT(DISTINCT cst_id) - COUNT(*) FILTER (WHERE cst_id IS NULL)
                                                                AS duplicate_id_rows,
    COUNT(*) FILTER (WHERE cst_firstname <> TRIM(cst_firstname)
                        OR cst_lastname  <> TRIM(cst_lastname)) AS names_with_extra_spaces
FROM bronze.crm_cust_info;

\echo 'Coded values (marital status / gender):'
SELECT 'marital_status' AS col, cst_marital_status AS value, COUNT(*) FROM bronze.crm_cust_info GROUP BY 2
UNION ALL
SELECT 'gender', cst_gndr, COUNT(*) FROM bronze.crm_cust_info GROUP BY 2
ORDER BY 1, 2;

\echo 'Example of a duplicated customer:'
SELECT cst_id, cst_key, cst_firstname, cst_lastname, cst_marital_status, cst_gndr, cst_create_date
FROM bronze.crm_cust_info
WHERE cst_id = (SELECT cst_id FROM bronze.crm_cust_info WHERE cst_id IS NOT NULL
                GROUP BY cst_id HAVING COUNT(*) > 1 ORDER BY COUNT(*) DESC, cst_id LIMIT 1)
ORDER BY cst_create_date;

\echo '########## crm_prd_info ##########'
SELECT
    COUNT(*)                                              AS total_rows,
    COUNT(*) - COUNT(DISTINCT prd_id)                     AS duplicate_id_rows,
    COUNT(*) FILTER (WHERE prd_cost IS NULL)              AS missing_cost,
    COUNT(*) FILTER (WHERE prd_cost < 0)                  AS negative_cost,
    COUNT(*) FILTER (WHERE prd_end_dt < prd_start_dt)     AS end_before_start,
    COUNT(DISTINCT prd_key)                               AS distinct_keys
FROM bronze.crm_prd_info;

\echo 'Product line codes:'
SELECT prd_line, COUNT(*) FROM bronze.crm_prd_info GROUP BY 1 ORDER BY 1;

\echo 'Example of a product with overlapping date ranges:'
SELECT prd_id, prd_key, prd_cost, prd_start_dt::date, prd_end_dt::date
FROM bronze.crm_prd_info
WHERE prd_key = (SELECT prd_key FROM bronze.crm_prd_info WHERE prd_end_dt < prd_start_dt ORDER BY prd_key LIMIT 1)
ORDER BY prd_start_dt;

\echo '########## crm_sales_details ##########'
SELECT
    COUNT(*)                                                         AS total_rows,
    COUNT(*) FILTER (WHERE sls_order_dt = 0 OR length(sls_order_dt::text) <> 8) AS bad_order_dates,
    COUNT(*) FILTER (WHERE sls_ship_dt  = 0 OR length(sls_ship_dt::text)  <> 8) AS bad_ship_dates,
    COUNT(*) FILTER (WHERE sls_due_dt   = 0 OR length(sls_due_dt::text)   <> 8) AS bad_due_dates,
    COUNT(*) FILTER (WHERE sls_order_dt > sls_ship_dt OR sls_order_dt > sls_due_dt) AS order_after_ship_or_due,
    COUNT(*) FILTER (WHERE sls_sales IS NULL OR sls_sales <= 0)      AS missing_or_neg_sales,
    COUNT(*) FILTER (WHERE sls_price IS NULL OR sls_price <= 0)      AS missing_or_neg_price,
    COUNT(*) FILTER (WHERE sls_sales <> sls_quantity * sls_price)    AS sales_not_qty_x_price
FROM bronze.crm_sales_details;

\echo 'Do sales point to products and customers that exist? (prd_key format differs, see silver)'
SELECT
    COUNT(*) FILTER (WHERE sls_prd_key NOT IN (SELECT SUBSTRING(prd_key FROM 7) FROM bronze.crm_prd_info)) AS unknown_product,
    COUNT(*) FILTER (WHERE sls_cust_id NOT IN (SELECT cst_id FROM bronze.crm_cust_info WHERE cst_id IS NOT NULL)) AS unknown_customer
FROM bronze.crm_sales_details;

\echo 'Examples of broken sales math:'
SELECT sls_ord_num, sls_quantity, sls_price, sls_sales, sls_quantity * ABS(sls_price) AS should_be
FROM bronze.crm_sales_details
WHERE sls_sales IS NULL OR sls_sales <= 0 OR sls_price IS NULL OR sls_price <= 0
   OR sls_sales <> sls_quantity * sls_price
ORDER BY sls_ord_num LIMIT 8;

\echo '########## erp_cust_az12 ##########'
SELECT
    COUNT(*)                                          AS total_rows,
    COUNT(*) FILTER (WHERE cid LIKE 'NAS%')           AS cid_with_nas_prefix,
    COUNT(*) FILTER (WHERE bdate > CURRENT_DATE)      AS birthdate_in_future,
    COUNT(*) FILTER (WHERE bdate < DATE '1925-01-01') AS birthdate_before_1925
FROM bronze.erp_cust_az12;

\echo 'Gender values:'
SELECT '"' || COALESCE(gen, 'NULL') || '"' AS gen, COUNT(*) FROM bronze.erp_cust_az12 GROUP BY 1 ORDER BY 1;

\echo '########## erp_loc_a101 ##########'
SELECT COUNT(*) AS total_rows, COUNT(*) FILTER (WHERE cid LIKE '%-%') AS cid_with_dash
FROM bronze.erp_loc_a101;

\echo 'Country values:'
SELECT '"' || COALESCE(cntry, 'NULL') || '"' AS cntry, COUNT(*) FROM bronze.erp_loc_a101 GROUP BY 1 ORDER BY 1;

\echo '########## erp_px_cat_g1v2 ##########'
SELECT
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE cat <> TRIM(cat) OR subcat <> TRIM(subcat) OR maintenance <> TRIM(maintenance)) AS extra_spaces
FROM bronze.erp_px_cat_g1v2;
SELECT maintenance, COUNT(*) FROM bronze.erp_px_cat_g1v2 GROUP BY 1 ORDER BY 1;
