/*
=============================================================
 Stored procedure: load silver layer (bronze -> silver)
=============================================================
 Purpose:
   Empties each silver table and refills it from bronze,
   cleaning the data on the way. Each fix below is based on a
   problem measured in analysis/01_profile_bronze.sql.

 How to run:
   CALL silver.load_silver();

 Why a procedure works here (but not for bronze):
   This step only moves data between tables inside the
   database. No files are read, so there are no Windows file
   permission problems.

 Error handling:
   If any step fails, PostgreSQL undoes the whole procedure,
   so silver is never left half loaded. The error is reported
   and then raised again, so the caller (a script, a
   scheduler, or CI) sees that the load FAILED. The SQL Server
   version only printed the error, so the job looked like it
   succeeded.

 Translation notes (SQL Server -> PostgreSQL):
   PRINT           -> RAISE NOTICE
   TRY / CATCH     -> BEGIN ... EXCEPTION WHEN OTHERS
   GETDATE()       -> clock_timestamp() for timing (now()
                      stays frozen at the start of the
                      transaction, so it can't measure time)
                      and CURRENT_DATE for "today"
   ISNULL()        -> COALESCE()
   LEN()           -> length()
=============================================================
*/

CREATE OR REPLACE PROCEDURE silver.load_silver()
LANGUAGE plpgsql
AS $$
DECLARE
    v_batch_start  TIMESTAMP := clock_timestamp();
    v_step_start   TIMESTAMP;
    v_rows         BIGINT;
BEGIN
    RAISE NOTICE '================================================';
    RAISE NOTICE 'Loading silver layer';
    RAISE NOTICE '================================================';

    -- ---------------------------------------------------------
    -- 1. crm_cust_info
    --    Problems found:
    --      - 4 rows with no customer ID (junk rows)
    --      - 5 customers appear 2-3 times; the newest row is
    --        the most complete one
    --      - 29 names with leading/trailing spaces
    --      - codes 'M'/'S' and 'M'/'F' instead of readable values
    -- ---------------------------------------------------------
    v_step_start := clock_timestamp();
    TRUNCATE TABLE silver.crm_cust_info;

    INSERT INTO silver.crm_cust_info (
        cst_id, cst_key, cst_firstname, cst_lastname,
        cst_marital_status, cst_gndr, cst_create_date
    )
    SELECT
        cst_id,
        TRIM(cst_key),
        TRIM(cst_firstname),
        TRIM(cst_lastname),
        CASE UPPER(TRIM(cst_marital_status))
            WHEN 'S' THEN 'Single'
            WHEN 'M' THEN 'Married'
            ELSE 'n/a'
        END,
        CASE UPPER(TRIM(cst_gndr))
            WHEN 'F' THEN 'Female'
            WHEN 'M' THEN 'Male'
            ELSE 'n/a'
        END,
        cst_create_date
    FROM (
        SELECT
            *,
            -- Number each customer's rows, newest first.
            -- Row 1 is the one to keep.
            ROW_NUMBER() OVER (PARTITION BY cst_id ORDER BY cst_create_date DESC) AS row_rank
        FROM bronze.crm_cust_info
        WHERE cst_id IS NOT NULL
    ) ranked
    WHERE row_rank = 1;

    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RAISE NOTICE '>> silver.crm_cust_info      % rows  (% ms)', v_rows,
        round(extract(epoch FROM clock_timestamp() - v_step_start) * 1000);

    -- ---------------------------------------------------------
    -- 2. crm_prd_info
    --    Problems found:
    --      - prd_key mixes two things: the first 5 characters
    --        are the category (CO-RF -> matches ERP id CO_RF),
    --        the rest is the product key used in sales
    --      - 2 products with no cost
    --      - product line codes M/R/S/T, 17 missing
    --      - 200 rows end before they start: the end dates
    --        are wrong. A product's price history is a chain:
    --        each version should end the day before the next
    --        version starts, so we rebuild end dates that way.
    -- ---------------------------------------------------------
    v_step_start := clock_timestamp();
    TRUNCATE TABLE silver.crm_prd_info;

    INSERT INTO silver.crm_prd_info (
        prd_id, cat_id, prd_key, prd_nm, prd_cost,
        prd_line, prd_start_dt, prd_end_dt
    )
    SELECT
        prd_id,
        REPLACE(SUBSTRING(prd_key FROM 1 FOR 5), '-', '_') AS cat_id,
        SUBSTRING(prd_key FROM 7)                          AS prd_key,
        TRIM(prd_nm),
        COALESCE(prd_cost, 0),
        CASE UPPER(TRIM(prd_line))
            WHEN 'M' THEN 'Mountain'
            WHEN 'R' THEN 'Road'
            WHEN 'S' THEN 'Other Sales'
            WHEN 'T' THEN 'Touring'
            ELSE 'n/a'
        END,
        prd_start_dt::date,
        -- LEAD looks at the NEXT row's start date for the same
        -- product. date - 1 = the day before. The newest
        -- version has no next row, so its end date is NULL
        -- (meaning: still current).
        LEAD(prd_start_dt::date) OVER (PARTITION BY prd_key ORDER BY prd_start_dt) - 1
    FROM bronze.crm_prd_info;

    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RAISE NOTICE '>> silver.crm_prd_info       % rows  (% ms)', v_rows,
        round(extract(epoch FROM clock_timestamp() - v_step_start) * 1000);

    -- ---------------------------------------------------------
    -- 3. crm_sales_details
    --    Problems found:
    --      - dates stored as integers (20101229); 19 order dates
    --        are invalid (0, 5489, 32154)
    --      - 13 rows with missing or negative sales
    --      - 12 rows with missing or negative price
    --      - sales <> quantity x price in 20 rows
    --    Business rule: sales = quantity x price.
    --      Price is trusted first (made positive if negative);
    --      sales is recalculated from it. If price is missing,
    --      it is derived from sales / quantity.
    --      (Checked: no row has BOTH values broken.)
    -- ---------------------------------------------------------
    v_step_start := clock_timestamp();
    TRUNCATE TABLE silver.crm_sales_details;

    INSERT INTO silver.crm_sales_details (
        sls_ord_num, sls_prd_key, sls_cust_id,
        sls_order_dt, sls_ship_dt, sls_due_dt,
        sls_sales, sls_quantity, sls_price
    )
    SELECT
        TRIM(sls_ord_num),
        TRIM(sls_prd_key),
        sls_cust_id,
        CASE WHEN sls_order_dt = 0 OR length(sls_order_dt::text) <> 8 THEN NULL
             ELSE to_date(sls_order_dt::text, 'YYYYMMDD') END,
        CASE WHEN sls_ship_dt = 0 OR length(sls_ship_dt::text) <> 8 THEN NULL
             ELSE to_date(sls_ship_dt::text, 'YYYYMMDD') END,
        CASE WHEN sls_due_dt = 0 OR length(sls_due_dt::text) <> 8 THEN NULL
             ELSE to_date(sls_due_dt::text, 'YYYYMMDD') END,
        CASE WHEN sls_sales IS NULL OR sls_sales <= 0
                  OR sls_sales <> sls_quantity * ABS(sls_price)
             THEN sls_quantity * ABS(sls_price)
             ELSE sls_sales END,
        sls_quantity,
        CASE WHEN sls_price IS NULL OR sls_price <= 0
             THEN COALESCE(ABS(sls_price), sls_sales / NULLIF(sls_quantity, 0))
             ELSE sls_price END
    FROM bronze.crm_sales_details;

    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RAISE NOTICE '>> silver.crm_sales_details  % rows  (% ms)', v_rows,
        round(extract(epoch FROM clock_timestamp() - v_step_start) * 1000);

    -- ---------------------------------------------------------
    -- 4. erp_cust_az12
    --    Problems found:
    --      - 11,042 IDs have an extra 'NAS' prefix
    --        (NASAW00011000 must match CRM key AW00011000)
    --      - 16 birthdates in the future -> impossible, NULL
    --      - gender written 8 different ways
    --        ('F', 'F ', 'Female', blanks, NULL, ...)
    -- ---------------------------------------------------------
    v_step_start := clock_timestamp();
    TRUNCATE TABLE silver.erp_cust_az12;

    INSERT INTO silver.erp_cust_az12 (cid, bdate, gen)
    SELECT
        CASE WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid FROM 4) ELSE cid END,
        CASE WHEN bdate > CURRENT_DATE THEN NULL ELSE bdate END,
        CASE
            WHEN UPPER(TRIM(gen)) IN ('F', 'FEMALE') THEN 'Female'
            WHEN UPPER(TRIM(gen)) IN ('M', 'MALE')   THEN 'Male'
            ELSE 'n/a'
        END
    FROM bronze.erp_cust_az12;

    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RAISE NOTICE '>> silver.erp_cust_az12      % rows  (% ms)', v_rows,
        round(extract(epoch FROM clock_timestamp() - v_step_start) * 1000);

    -- ---------------------------------------------------------
    -- 5. erp_loc_a101
    --    Problems found:
    --      - every ID has a dash (AW-00011000 vs AW00011000)
    --      - the same country written different ways:
    --        'DE' / 'Germany', 'US' / 'USA' / 'United States'
    --      - 337 blank or missing countries
    -- ---------------------------------------------------------
    v_step_start := clock_timestamp();
    TRUNCATE TABLE silver.erp_loc_a101;

    INSERT INTO silver.erp_loc_a101 (cid, cntry)
    SELECT
        REPLACE(cid, '-', ''),
        CASE
            WHEN TRIM(cntry) = 'DE'                THEN 'Germany'
            WHEN TRIM(cntry) IN ('US', 'USA')      THEN 'United States'
            WHEN cntry IS NULL OR TRIM(cntry) = '' THEN 'n/a'
            ELSE TRIM(cntry)
        END
    FROM bronze.erp_loc_a101;

    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RAISE NOTICE '>> silver.erp_loc_a101       % rows  (% ms)', v_rows,
        round(extract(epoch FROM clock_timestamp() - v_step_start) * 1000);

    -- ---------------------------------------------------------
    -- 6. erp_px_cat_g1v2
    --    No problems found: copied as-is.
    -- ---------------------------------------------------------
    v_step_start := clock_timestamp();
    TRUNCATE TABLE silver.erp_px_cat_g1v2;

    INSERT INTO silver.erp_px_cat_g1v2 (id, cat, subcat, maintenance)
    SELECT id, cat, subcat, maintenance
    FROM bronze.erp_px_cat_g1v2;

    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RAISE NOTICE '>> silver.erp_px_cat_g1v2    % rows  (% ms)', v_rows,
        round(extract(epoch FROM clock_timestamp() - v_step_start) * 1000);

    RAISE NOTICE '================================================';
    RAISE NOTICE 'Silver layer loaded in % ms',
        round(extract(epoch FROM clock_timestamp() - v_batch_start) * 1000);
    RAISE NOTICE '================================================';

EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '================================================';
    RAISE NOTICE 'ERROR while loading silver layer: %', SQLERRM;
    RAISE NOTICE 'Error code: %', SQLSTATE;
    RAISE NOTICE '================================================';
    RAISE;  -- re-raise so the caller knows the load failed
END;
$$;
