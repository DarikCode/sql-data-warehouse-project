"""
Data access for the dashboard.

Every number in the dashboard comes from the warehouse's gold layer
(the star schema) or from the etl run log. The heavy lifting - the
star-schema join and the age calculations - is done in SQL by
PostgreSQL; pandas only filters and groups the result for the charts.

Connection settings use the standard PostgreSQL environment variables
(PGHOST, PGPORT, PGUSER, PGDATABASE). The password is never stored
here: psycopg reads it from pgpass.conf / ~/.pgpass or PGPASSWORD,
exactly like psql does.
"""

import os

import pandas as pd
import psycopg
import streamlit as st


class WarehouseUnavailable(Exception):
    """Raised when the dashboard cannot reach the PostgreSQL warehouse."""


def _connection_settings() -> dict:
    return {
        "host": os.getenv("PGHOST", "localhost"),
        "port": int(os.getenv("PGPORT", "5432")),
        "user": os.getenv("PGUSER", "postgres"),
        "dbname": os.getenv("PGDATABASE", "datawarehouse"),
        "connect_timeout": 5,
    }


def run_query(sql: str) -> pd.DataFrame:
    """Run a SELECT against the warehouse and return it as a DataFrame."""
    try:
        with psycopg.connect(**_connection_settings()) as conn:
            cur = conn.execute(sql)
            columns = [col.name for col in cur.description]
            return pd.DataFrame(cur.fetchall(), columns=columns)
    except psycopg.OperationalError as exc:
        raise WarehouseUnavailable(str(exc)) from exc


# ---------------------------------------------------------------------------
# Sales: the star schema joined into one wide table (one row per order line)
# ---------------------------------------------------------------------------
SALES_SQL = """
SELECT
    f.order_number,
    f.order_date,
    f.sales_amount,
    f.quantity,
    f.price,
    c.customer_key,
    c.country,
    c.gender,
    c.marital_status,
    -- age of the customer on the day of the order
    EXTRACT(YEAR FROM age(f.order_date, c.birthdate))::int AS age_at_order,
    p.product_key,
    p.cost AS unit_cost,
    p.product_name,
    p.category,
    p.subcategory,
    p.product_line
FROM gold.fact_sales f
JOIN gold.dim_customers c ON c.customer_key = f.customer_key
JOIN gold.dim_products  p ON p.product_key  = f.product_key
"""


@st.cache_data(ttl=600, show_spinner="Loading sales from the warehouse...")
def load_sales() -> pd.DataFrame:
    df = run_query(SALES_SQL)
    df["order_date"] = pd.to_datetime(df["order_date"])
    df["order_year"] = df["order_date"].dt.year.astype("Int64")
    df["order_month"] = df["order_date"].dt.to_period("M").dt.to_timestamp()
    return df


# ---------------------------------------------------------------------------
# Pipeline run log (etl schema)
# ---------------------------------------------------------------------------
@st.cache_data(ttl=30, show_spinner=False)
def load_runs() -> pd.DataFrame:
    return run_query("""
        SELECT run_id, started_at, finished_at, duration_ms, status, run_by, rebuild
        FROM etl.pipeline_runs
        ORDER BY run_id
    """)


@st.cache_data(ttl=30, show_spinner=False)
def load_steps() -> pd.DataFrame:
    return run_query("""
        SELECT run_id, step_order, step_name, status, duration_ms, rows_in_layer, message
        FROM etl.step_log
        ORDER BY run_id, step_order
    """)
