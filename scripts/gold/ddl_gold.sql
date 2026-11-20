/*
=============================================================
 DDL: Create gold views (star schema)
=============================================================
 Purpose:
   The gold layer is what analysts and dashboards use. It
   combines the six silver tables into three business-friendly
   objects, arranged as a STAR SCHEMA:

                 dim_customers
                       |
                  fact_sales        (one row per order line)
                       |
                 dim_products

   - Dimensions describe things: WHO bought (customers),
     WHAT was bought (products).
   - The fact table records events: each sale, with its
     numbers (amount, quantity, price) and keys pointing to
     the dimensions.

   Column names are renamed from source-system codes
   (cst_gndr, prd_nm) to plain English (gender, product_name),
   so nobody needs to know the source systems to use them.

 Why views, not tables:
   A view stores only the query. Gold always shows the latest
   silver data, with no extra load step. With 60k sales rows
   that is fast enough. (At a larger scale, or to keep
   history, gold would become real tables.)

 How to run:
   psql -U postgres -h localhost -d datawarehouse -v ON_ERROR_STOP=1 -f scripts/gold/ddl_gold.sql

 Differences from the SQL Server version:
   - The views are dropped in dependency order (fact first,
     because it reads from the two dimensions).
   - Missing country / category show 'n/a' instead of NULL,
     the same convention silver uses for unknown values.
=============================================================
*/

DROP VIEW IF EXISTS gold.fact_sales;
DROP VIEW IF EXISTS gold.dim_customers;
DROP VIEW IF EXISTS gold.dim_products;

-- =============================================================
-- Dimension: gold.dim_customers
--   One row per customer. CRM is the main source; the ERP
--   adds birthdate, country, and fills in missing gender.
-- =============================================================
CREATE VIEW gold.dim_customers AS
SELECT
    -- Surrogate key: a simple number owned by the warehouse,
    -- independent of either source system's IDs.
    ROW_NUMBER() OVER (ORDER BY ci.cst_id) AS customer_key,
    ci.cst_id                              AS customer_id,
    ci.cst_key                             AS customer_number,
    ci.cst_firstname                       AS first_name,
    ci.cst_lastname                        AS last_name,
    COALESCE(la.cntry, 'n/a')              AS country,
    ci.cst_marital_status                  AS marital_status,
    -- Data integration rule: CRM is the master for gender.
    -- The ERP is only used when the CRM value is unknown.
    -- (Fills 4,554 gaps; in 57 cases the systems disagree
    --  and the CRM value wins.)
    CASE
        WHEN ci.cst_gndr <> 'n/a' THEN ci.cst_gndr
        ELSE COALESCE(ca.gen, 'n/a')
    END                                    AS gender,
    ca.bdate                               AS birthdate,
    ci.cst_create_date                     AS create_date
FROM silver.crm_cust_info ci
LEFT JOIN silver.erp_cust_az12 ca
       ON ci.cst_key = ca.cid
LEFT JOIN silver.erp_loc_a101 la
       ON ci.cst_key = la.cid;

-- =============================================================
-- Dimension: gold.dim_products
--   One row per product, current version only. Older price
--   versions are history (prd_end_dt is set) and are left out.
-- =============================================================
CREATE VIEW gold.dim_products AS
SELECT
    ROW_NUMBER() OVER (ORDER BY pn.prd_start_dt, pn.prd_key) AS product_key,
    pn.prd_id                    AS product_id,
    pn.prd_key                   AS product_number,
    pn.prd_nm                    AS product_name,
    pn.cat_id                    AS category_id,
    -- 7 pedal products have category ID 'CO_PE', which does
    -- not exist in the ERP category list (a source data gap).
    COALESCE(pc.cat, 'n/a')      AS category,
    COALESCE(pc.subcat, 'n/a')   AS subcategory,
    COALESCE(pc.maintenance, 'n/a') AS maintenance,
    pn.prd_cost                  AS cost,
    pn.prd_line                  AS product_line,
    pn.prd_start_dt              AS start_date
FROM silver.crm_prd_info pn
LEFT JOIN silver.erp_px_cat_g1v2 pc
       ON pn.cat_id = pc.id
WHERE pn.prd_end_dt IS NULL;

-- =============================================================
-- Fact: gold.fact_sales
--   One row per order line. The source IDs are swapped for
--   the dimensions' surrogate keys, so the fact table connects
--   to the star schema only through warehouse keys.
-- =============================================================
CREATE VIEW gold.fact_sales AS
SELECT
    sd.sls_ord_num   AS order_number,
    pr.product_key   AS product_key,
    cu.customer_key  AS customer_key,
    sd.sls_order_dt  AS order_date,
    sd.sls_ship_dt   AS shipping_date,
    sd.sls_due_dt    AS due_date,
    sd.sls_sales     AS sales_amount,
    sd.sls_quantity  AS quantity,
    sd.sls_price     AS price
FROM silver.crm_sales_details sd
LEFT JOIN gold.dim_products pr
       ON sd.sls_prd_key = pr.product_number
LEFT JOIN gold.dim_customers cu
       ON sd.sls_cust_id = cu.customer_id;
