"""
Sales Data Warehouse dashboard (Streamlit).

Run from the project root:
    .venv\\Scripts\\streamlit run dashboard/app.py

This file sets up the page, loads the data once, draws the sidebar
filters, and hands the filtered sales to whichever page is open.
"""

import pandas as pd
import streamlit as st

from data import WarehouseUnavailable, load_runs, load_sales
from ui import inject_css

st.set_page_config(page_title="Sales Data Warehouse", page_icon=":material/database:", layout="wide")
inject_css()

pages = [
    st.Page("views/overview.py", title="Sales overview", icon=":material/insights:", default=True),
    st.Page("views/customers.py", title="Customers", icon=":material/group:"),
    st.Page("views/products.py", title="Products", icon=":material/pedal_bike:"),
    st.Page("views/pipeline.py", title="Pipeline health", icon=":material/monitor_heart:"),
]
nav = st.navigation(pages, position="top")

# --------------------------------------------------------------------------
# Load the warehouse data (cached for 10 minutes)
# --------------------------------------------------------------------------
try:
    sales = load_sales()
    runs = load_runs()
except WarehouseUnavailable as exc:
    st.error(
        "**Can't reach the PostgreSQL warehouse.**\n\n"
        "Check that PostgreSQL is running, that the pipeline has been run "
        "(`.\\run_pipeline.ps1 -Rebuild`), and that your password is in "
        "pgpass.conf or the PGPASSWORD variable.",
        icon=":material/error:",
    )
    with st.expander("Technical details"):
        st.code(str(exc))
    st.stop()

# Data freshness: the last pipeline run that loaded the data successfully
ok_runs = runs[runs["status"] == "success"]
if not ok_runs.empty:
    last_ok = ok_runs.iloc[-1]
    st.session_state["freshness"] = (
        f"Data loaded {last_ok['finished_at'].strftime('%d %b %Y, %H:%M')} · run #{last_ok['run_id']}"
    )
else:
    st.session_state["freshness"] = "No successful pipeline run logged"

# --------------------------------------------------------------------------
# Sidebar: brand, filters, what the data covers
# --------------------------------------------------------------------------
with st.sidebar:
    st.markdown(
        '<div class="brand"><div class="brand-mark">DW</div><div>'
        '<div class="brand-name">Sales Data Warehouse</div>'
        '<div class="brand-sub">PostgreSQL · bronze → silver → gold</div></div></div>',
        unsafe_allow_html=True,
    )

    st.markdown('<div class="side-label">Filters</div>', unsafe_allow_html=True)
    years = sorted(sales["order_year"].dropna().unique().tolist())
    year_from, year_to = st.select_slider("Order year", options=years, value=(years[0], years[-1]))
    countries = st.multiselect("Country", sorted(sales["country"].unique()), placeholder="All countries")
    categories = st.multiselect("Category", sorted(sales["category"].unique()), placeholder="All categories")
    st.caption("Filters apply to Sales overview, Customers and Products.")

    st.divider()
    st.markdown('<div class="side-label">Data in this dashboard</div>', unsafe_allow_html=True)
    st.markdown(
        f'<div class="side-info">Source: <b>gold</b> star schema<br>'
        f'<b>{len(sales):,}</b> order lines · <b>{sales["order_number"].nunique():,}</b> orders<br>'
        f'<b>{sales["customer_key"].nunique():,}</b> customers · <b>{sales["product_key"].nunique()}</b> products sold<br>'
        f'Orders from <b>{sales["order_date"].min():%b %Y}</b> to <b>{sales["order_date"].max():%b %Y}</b></div>',
        unsafe_allow_html=True,
    )
    st.write("")
    if st.button("Reload data", icon=":material/refresh:", width="stretch"):
        st.cache_data.clear()
        st.rerun()

# --------------------------------------------------------------------------
# Apply the filters
# --------------------------------------------------------------------------
if (year_from, year_to) == (years[0], years[-1]):
    # Full range: keep everything, including the 19 order lines whose
    # order date was invalid in the source (NULL after cleaning).
    mask = pd.Series(True, index=sales.index)
else:
    mask = sales["order_year"].between(year_from, year_to).fillna(False)
if countries:
    mask &= sales["country"].isin(countries)
if categories:
    mask &= sales["category"].isin(categories)

st.session_state["sales"] = sales[mask]
st.session_state["filter_chips"] = [
    f"{year_from}–{year_to}" if year_from != year_to else str(year_from),
    ", ".join(countries) if countries else "All countries",
    ", ".join(categories) if categories else "All categories",
]

nav.run()
