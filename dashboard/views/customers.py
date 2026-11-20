"""Customers: where they are, who they are, and what they spend."""

import pandas as pd
import streamlit as st

from charts import CONFIG, fmt_number, hbar, vbar
from ui import card, kpi_row, page_header, source_footer

sales: pd.DataFrame = st.session_state["sales"]

page_header("Business", "Customers",
            "Where customers live, who they are, and how much they spend.",
            chips=st.session_state["filter_chips"], fresh=st.session_state["freshness"])

if sales.empty:
    st.info("No sales match the current filters.", icon=":material/filter_alt_off:")
    st.stop()

# One row per customer: total spend and age at their first order
per_customer = (
    sales.sort_values("order_date")  # undated lines sort last; 'first' skips their missing age
    .groupby("customer_key")
    .agg(spent=("sales_amount", "sum"), age=("age_at_order", "first"),
         country=("country", "first"), gender=("gender", "first"),
         marital_status=("marital_status", "first"), orders=("order_number", "nunique"))
    .reset_index()
)
repeat_share = (per_customer["orders"] > 1).mean()

kpi_row([
    {"label": "Customers", "value": f"{len(per_customer):,}", "foot": "with at least one order"},
    {"label": "Average spend per customer", "value": f"{per_customer['spent'].mean():,.0f}",
     "foot": f"median {per_customer['spent'].median():,.0f}"},
    {"label": "Repeat customers", "value": f"{repeat_share:.0%}", "foot": "placed more than one order"},
    {"label": "Average age at first order", "value": f"{per_customer['age'].mean():.0f}",
     "foot": "years, from ERP birthdates"},
])

left, right = st.columns(2, gap="medium")
with left:
    by_country = sales.groupby("country")["sales_amount"].sum().sort_values(ascending=False).reset_index()
    with card("Revenue by country", "Country of residence from the ERP system",
              note="'n/a': customers whose country is missing in the source."):
        st.plotly_chart(
            hbar(by_country["country"], by_country["sales_amount"], "Revenue",
                 value_text=[fmt_number(v) for v in by_country["sales_amount"]], height=320),
            width="stretch", config=CONFIG, theme=None,
        )

with right:
    bins = [0, 30, 40, 50, 60, 200]
    labels = ["Under 30", "30–39", "40–49", "50–59", "60+"]
    ages = per_customer.dropna(subset=["age"]).copy()
    ages["age_group"] = pd.cut(ages["age"], bins=bins, labels=labels, right=False)
    by_age = (
        ages.groupby("age_group", observed=False)
        .agg(avg_spent=("spent", "mean"), customers=("customer_key", "count"))
        .reset_index()
    )
    with card("Average spend by age group", "Age at first order; younger customers spend more",
              note="Birthdate (ERP) combined with order dates (CRM)."):
        st.plotly_chart(
            vbar(by_age["age_group"].astype(str), by_age["avg_spent"], "Average spend",
                 value_text=[f"{v:,.0f}" for v in by_age["avg_spent"]], height=320),
            width="stretch", config=CONFIG, theme=None,
        )

left, right = st.columns(2, gap="medium")
with left:
    by_gender = per_customer.groupby("gender")["customer_key"].count().sort_values(ascending=False).reset_index()
    with card("Customers by gender", "CRM value, filled from the ERP where the CRM had none"):
        st.plotly_chart(
            hbar(by_gender["gender"], by_gender["customer_key"], "Customers",
                 value_text=[f"{v:,} · {v / len(per_customer):.0%}" for v in by_gender["customer_key"]], room=1.5),
            width="stretch", config=CONFIG, theme=None,
        )
with right:
    by_marital = (
        per_customer.groupby("marital_status")
        .agg(customers=("customer_key", "count"), avg_spent=("spent", "mean"))
        .sort_values("customers", ascending=False).reset_index()
    )
    with card("Customers by marital status", "With average spend per customer"):
        st.plotly_chart(
            hbar(by_marital["marital_status"], by_marital["customers"], "Customers",
                 value_text=[f"{c:,} · avg spend {s:,.0f}" for c, s in
                             zip(by_marital["customers"], by_marital["avg_spent"])], room=1.8),
            width="stretch", config=CONFIG, theme=None,
        )

with st.expander("Age groups as a table"):
    st.dataframe(
        by_age.rename(columns={"age_group": "Age group", "avg_spent": "Average spend", "customers": "Customers"}),
        hide_index=True, width="stretch",
        column_config={"Average spend": st.column_config.NumberColumn(format="%.0f")},
    )

source_footer("Source: gold.dim_customers (CRM customers enriched with ERP birthdate, gender and country) "
              "joined to gold.fact_sales.")
