"""Products: what sells, and which categories earn the best margin."""

import pandas as pd
import streamlit as st

from charts import CONFIG, fmt_number, hbar
from ui import card, kpi_row, page_header, source_footer

sales: pd.DataFrame = st.session_state["sales"]

page_header("Business", "Products",
            "Which products bring in the revenue, and which earn the best margin.",
            chips=st.session_state["filter_chips"], fresh=st.session_state["freshness"])

if sales.empty:
    st.info("No sales match the current filters.", icon=":material/filter_alt_off:")
    st.stop()

# Estimated gross profit: revenue minus (current product cost x quantity)
sales = sales.assign(est_profit=sales["sales_amount"] - sales["unit_cost"] * sales["quantity"])

by_product = (
    sales.groupby(["product_name", "category", "subcategory"])
    .agg(revenue=("sales_amount", "sum"), units=("quantity", "sum"),
         orders=("order_number", "nunique"), profit=("est_profit", "sum"))
    .sort_values("revenue", ascending=False)
    .reset_index()
)
by_product["margin"] = by_product["profit"] / by_product["revenue"] * 100
top_share = by_product["revenue"].head(10).sum() / by_product["revenue"].sum()
margin_total = sales["est_profit"].sum() / sales["sales_amount"].sum()

kpi_row([
    {"label": "Products sold", "value": f"{len(by_product):,}", "foot": "of 295 products in the catalogue"},
    {"label": "Units sold", "value": f"{sales['quantity'].sum():,}", "foot": f"{fmt_number(sales['sales_amount'].sum())} revenue"},
    {"label": "Top 10 products", "value": f"{top_share:.0%}", "foot": "of revenue"},
    {"label": "Estimated gross margin", "value": f"{margin_total:.1%}", "foot": "based on current product cost"},
])

left, right = st.columns(2, gap="medium")
with left:
    by_sub = sales.groupby("subcategory")["sales_amount"].sum().sort_values(ascending=False).head(10).reset_index()
    with card("Top 10 subcategories", "By revenue"):
        st.plotly_chart(
            hbar(by_sub["subcategory"], by_sub["sales_amount"], "Revenue",
                 value_text=[fmt_number(v) for v in by_sub["sales_amount"]], height=430),
            width="stretch", config=CONFIG, theme=None,
        )
with right:
    by_cat = (
        sales.groupby("category")
        .agg(revenue=("sales_amount", "sum"), profit=("est_profit", "sum"))
        .assign(margin=lambda d: d["profit"] / d["revenue"] * 100)
        .sort_values("margin", ascending=False).reset_index()
    )
    with card("Estimated gross margin by category", "Profit as a share of revenue",
              note="Uses each product's current cost; 77 products changed cost over time, "
                   "so older sales are approximate."):
        st.plotly_chart(
            hbar(by_cat["category"], by_cat["margin"], "Margin %",
                 value_text=[f"{m:.1f}% · profit {fmt_number(p)}" for m, p in zip(by_cat["margin"], by_cat["profit"])],
                 height=200, room=1.8),
            width="stretch", config=CONFIG, theme=None,
        )
    by_line = sales.groupby("product_line")["sales_amount"].sum().sort_values(ascending=False).reset_index()
    with card("Revenue by product line"):
        st.plotly_chart(
            hbar(by_line["product_line"], by_line["sales_amount"], "Revenue",
                 value_text=[fmt_number(v) for v in by_line["sales_amount"]], height=200),
            width="stretch", config=CONFIG, theme=None,
        )

with card("Top 20 products", "By revenue"):
    st.dataframe(
        by_product.head(20)[["product_name", "category", "subcategory", "revenue", "units", "orders", "margin"]]
        .rename(columns={"product_name": "Product", "category": "Category", "subcategory": "Subcategory",
                         "revenue": "Revenue", "units": "Units", "orders": "Orders", "margin": "Est. margin"}),
        hide_index=True, width="stretch", height=36 * 20 + 40,  # show all 20 rows, no inner scroll
        column_config={
            "Revenue": st.column_config.ProgressColumn(format="%d", min_value=0,
                                                       max_value=int(by_product["revenue"].max())),
            "Est. margin": st.column_config.NumberColumn(format="%.1f%%"),
        },
    )
    st.write("")

source_footer("Source: gold.dim_products (current version of each product, categories from the ERP) "
              "joined to gold.fact_sales. 165 catalogue products never sold and do not appear here.")
