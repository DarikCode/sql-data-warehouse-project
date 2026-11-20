/*
=============================================================
 Load bronze layer (CSV files -> bronze tables)
=============================================================
 Purpose:
   Empties each bronze table and reloads it from its CSV file
   ("truncate and insert", a full load).

 How to run (from the project root folder, because the file
 paths below are relative to it):
   psql -U postgres -h localhost -d datawarehouse -v ON_ERROR_STOP=1 -f scripts/bronze/load_bronze.sql

 Why this is a psql script, not a stored procedure:
   The SQL Server version uses a procedure with BULK INSERT,
   where the database server itself opens the CSV files.
   PostgreSQL's equivalent, COPY ... FROM 'file', has the same
   problem as BULK INSERT: the server process must be allowed
   to read the folder, which on Windows it usually is not.
   psql's \copy reads the file on the client side (as you)
   and streams it to the server, so it works on any machine,
   including GitHub Actions, without file permissions setup.

 Safety:
   Everything runs in one transaction. If any file fails to
   load, ALL tables are rolled back to their previous state,
   so bronze is never left half loaded.
=============================================================
*/

\timing on
\echo '================================================'
\echo 'Loading bronze layer'
\echo '================================================'

BEGIN;

\echo '------------- CRM tables -------------'

\echo '>> bronze.crm_cust_info'
TRUNCATE TABLE bronze.crm_cust_info;
\copy bronze.crm_cust_info FROM 'datasets/source_crm/cust_info.csv' WITH (FORMAT csv, HEADER true)

\echo '>> bronze.crm_prd_info'
TRUNCATE TABLE bronze.crm_prd_info;
\copy bronze.crm_prd_info FROM 'datasets/source_crm/prd_info.csv' WITH (FORMAT csv, HEADER true)

\echo '>> bronze.crm_sales_details'
TRUNCATE TABLE bronze.crm_sales_details;
\copy bronze.crm_sales_details FROM 'datasets/source_crm/sales_details.csv' WITH (FORMAT csv, HEADER true)

\echo '------------- ERP tables -------------'

\echo '>> bronze.erp_loc_a101'
TRUNCATE TABLE bronze.erp_loc_a101;
\copy bronze.erp_loc_a101 FROM 'datasets/source_erp/LOC_A101.csv' WITH (FORMAT csv, HEADER true)

\echo '>> bronze.erp_cust_az12'
TRUNCATE TABLE bronze.erp_cust_az12;
\copy bronze.erp_cust_az12 FROM 'datasets/source_erp/CUST_AZ12.csv' WITH (FORMAT csv, HEADER true)

\echo '>> bronze.erp_px_cat_g1v2'
TRUNCATE TABLE bronze.erp_px_cat_g1v2;
\copy bronze.erp_px_cat_g1v2 FROM 'datasets/source_erp/PX_CAT_G1V2.csv' WITH (FORMAT csv, HEADER true)

COMMIT;

\timing off
\echo '================================================'
\echo 'Bronze layer loaded. Row counts:'
\echo '================================================'
SELECT 'crm_cust_info'     AS table_name, COUNT(*) AS row_count FROM bronze.crm_cust_info
UNION ALL SELECT 'crm_prd_info',      COUNT(*) FROM bronze.crm_prd_info
UNION ALL SELECT 'crm_sales_details', COUNT(*) FROM bronze.crm_sales_details
UNION ALL SELECT 'erp_loc_a101',      COUNT(*) FROM bronze.erp_loc_a101
UNION ALL SELECT 'erp_cust_az12',     COUNT(*) FROM bronze.erp_cust_az12
UNION ALL SELECT 'erp_px_cat_g1v2',   COUNT(*) FROM bronze.erp_px_cat_g1v2;
