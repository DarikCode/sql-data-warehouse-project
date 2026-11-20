# Data catalog: gold layer

The gold layer is the business-facing part of the warehouse. It is a **star schema**: one fact table of sales events, connected to two dimension tables that describe who bought and what was bought. All three are views over the silver layer, so they always show the latest loaded data.

Unknown values are shown as `n/a` rather than left empty, except for dates and numbers, which use NULL.

---

## gold.dim_customers

One row per customer (18,484 rows). Combines the CRM customer record with birthdate, gender and country from the ERP.

| Column | Type | Description | Source |
|---|---|---|---|
| customer_key | BIGINT | Surrogate key: a number owned by the warehouse that identifies the customer. Used to join to `fact_sales`. | Generated |
| customer_id | INT | The customer's numeric ID in the CRM. | CRM `cst_id` |
| customer_number | VARCHAR(50) | The customer's alphanumeric code, e.g. `AW00011000`. Used to match customers across the two systems. | CRM `cst_key` |
| first_name | VARCHAR(50) | First name, with extra spaces removed. | CRM |
| last_name | VARCHAR(50) | Last name, with extra spaces removed. | CRM |
| country | VARCHAR(50) | Country of residence, e.g. `Germany`, `United States`. `n/a` if unknown. | ERP `LOC_A101` |
| marital_status | VARCHAR(50) | `Married`, `Single` or `n/a`. | CRM |
| gender | VARCHAR(50) | `Male`, `Female` or `n/a`. Taken from the CRM; the ERP value is only used when the CRM value is unknown. | CRM, then ERP `CUST_AZ12` |
| birthdate | DATE | Date of birth. NULL if missing or impossible (in the future). | ERP `CUST_AZ12` |
| create_date | DATE | When the customer was created in the CRM. | CRM |

---

## gold.dim_products

One row per product, **current version only** (295 rows). Older price versions of a product are history and are left out. Combines the CRM product record with its category from the ERP.

| Column | Type | Description | Source |
|---|---|---|---|
| product_key | BIGINT | Surrogate key identifying the product. Used to join to `fact_sales`. | Generated |
| product_id | INT | The product's numeric ID in the CRM. | CRM `prd_id` |
| product_number | VARCHAR(50) | The product's code, e.g. `BK-R93R-62`. Used by sales records. | CRM `prd_key` (characters 7+) |
| product_name | VARCHAR(50) | Descriptive name including type, color and size, e.g. `Road-150 Red- 62`. | CRM |
| category_id | VARCHAR(50) | Code linking the product to its category, e.g. `BI_RB`. | CRM `prd_key` (first 5 characters) |
| category | VARCHAR(50) | High-level group: `Bikes`, `Components`, `Clothing`, `Accessories`. `n/a` for 7 pedal products whose category is missing in the ERP. | ERP `PX_CAT_G1V2` |
| subcategory | VARCHAR(50) | Detailed group, e.g. `Mountain Bikes`, `Helmets`. | ERP `PX_CAT_G1V2` |
| maintenance | VARCHAR(50) | Whether the product needs maintenance: `Yes` / `No`. | ERP `PX_CAT_G1V2` |
| cost | INT | Cost of the product. 0 if unknown. | CRM |
| product_line | VARCHAR(50) | `Mountain`, `Road`, `Touring`, `Other Sales` or `n/a`. | CRM |
| start_date | DATE | Date this version of the product (and its cost) took effect. | CRM |

---

## gold.fact_sales

One row per order line (60,398 rows). Each row is one product on one order.

| Column | Type | Description | Source |
|---|---|---|---|
| order_number | VARCHAR(50) | Sales order ID, e.g. `SO43697`. An order with several products has several rows. | CRM |
| product_key | BIGINT | Links to `dim_products.product_key`. | Looked up |
| customer_key | BIGINT | Links to `dim_customers.customer_key`. | Looked up |
| order_date | DATE | When the order was placed. NULL for 19 orders with an invalid date in the source. | CRM |
| shipping_date | DATE | When the order was shipped. | CRM |
| due_date | DATE | When payment was due. | CRM |
| sales_amount | INT | Revenue for the line, always quantity × price. | CRM, corrected |
| quantity | INT | Number of units. | CRM |
| price | INT | Price per unit. | CRM, corrected |

---

## etl schema (pipeline metadata)

Not business data: these tables record how the pipeline itself ran.

**etl.pipeline_runs**: one row per run of `run_pipeline.ps1`

| Column | Description |
|---|---|
| run_id | Run number |
| started_at, finished_at, duration_ms | Timing of the whole run |
| status | `running`, `success` or `failed` |
| run_by | Database user that ran it |
| rebuild | Whether the run recreated the database from scratch |

**etl.step_log**: one row per step of each run

| Column | Description |
|---|---|
| step_id, run_id, step_order | Identify the step and its run |
| step_name | `bronze_load`, `silver_load`, `silver_checks`, `gold_refresh` or `gold_checks` |
| started_at, finished_at, duration_ms | Timing of the step |
| status | `running`, `success`, `failed` or `skipped` (not run because an earlier step failed) |
| rows_in_layer | Total rows in the layer after the step: a sudden drop signals a problem |
| message | Error details when the step failed |
