"""Sales overview: headline numbers and how sales developed over time."""

import pandas as pd
import streamlit as st

from charts import CONFIG, fmt_number, hbar, line
from ui import card, kpi_row, page_header, source_footer

sales: pd.DataFrame = st.session_state["sales"]

page_header("Business", "Sales overview",
            "How revenue and customers developed, and what drives revenue.",
            chips=st.session_state["filter_chips"], fresh=st.session_state["freshness"])

if sales.empty:
    st.info("No sales match the current filters.", icon=":material/filter_alt_off:")
    st.stop()

# ---------------- Headline numbers ----------------
revenue = sales["sales_amount"].sum()
orders = sales["order_number"].nunique()
customers = sales["customer_key"].nunique()

by_year = sales.groupby("order_year")["sales_amount"].sum()
yoy = None
if 2012 in by_year.index and 2013 in by_year.index:
    yoy = by_year[2013] / by_year[2012] - 1  # the last two full years

kpi_row([
    {"label": "Revenue", "value": fmt_number(revenue),
     "foot": "2013 vs 2012" if yoy is not None else "selected period", "delta": yoy},
    {"label": "Orders", "value": f"{orders:,}", "foot": f"{len(sales):,} order lines"},
    {"label": "Customers", "value": f"{customers:,}", "foot": f"{orders / customers:.1f} orders per customer"},
    {"label": "Average order value", "value": f"{revenue / orders:,.0f}", "foot": "revenue ÷ orders"},
    {"label": "Units sold", "value": f"{sales['quantity'].sum():,}", "foot": f"{sales['product_key'].nunique()} different products"},
])

# ---------------- Monthly trend ----------------
dated = sales.dropna(subset=["order_month"])
monthly = (
    dated.groupby("order_month")
    .agg(revenue=("sales_amount", "sum"), customers=("customer_key", "nunique"))
    .reset_index()
)
LAUNCH = pd.Timestamp("2012-12-01")
show_launch = not monthly.empty and monthly["order_month"].min() <= LAUNCH <= monthly["order_month"].max()


def mark_launch(fig, label=True):
    if show_launch:
        fig.add_vline(x=LAUNCH, line=dict(color="#c3c2b7", width=1))
        if label:
            fig.add_annotation(x=LAUNCH, y=1, yref="paper", text="Accessories & clothing launch",
                               showarrow=False, xanchor="right", yanchor="top", xshift=-6,
                               font=dict(size=11, color="#52514e"))
    return fig


left, right = st.columns([2, 1], gap="medium")
with left:
    with card("Revenue per month", "Sum of sales amount by order month",
              note="Dec 2010 and Jan 2014 are only partly covered by the data."):
        st.plotly_chart(mark_launch(line(monthly["order_month"], monthly["revenue"], "Revenue")),
                        width="stretch", config=CONFIG, theme=None)
with right:
    by_category = sales.groupby("category")["sales_amount"].sum().sort_values(ascending=False).reset_index()
    share = by_category["sales_amount"] / by_category["sales_amount"].sum()
    with card("Revenue by category", "Share of total revenue"):
        st.plotly_chart(
            hbar(by_category["category"], by_category["sales_amount"], "Revenue",
                 value_text=[f"{fmt_number(v)} · {s:.1%}" for v, s in zip(by_category["sales_amount"], share)],
                 height=290, room=1.9),
            width="stretch", config=CONFIG, theme=None,
        )

left, right = st.columns([2, 1], gap="medium")
with left:
    with card("Buying customers per month", "Distinct customers with at least one order that month"):
        st.plotly_chart(mark_launch(line(monthly["order_month"], monthly["customers"], "Customers"), label=False),
                        width="stretch", config=CONFIG, theme=None)
with right:
    with card("What happened in 2013", "Across all data, 2012 vs 2013 monthly averages"):
        st.markdown(
            '<div class="insight">'
            '<div class="big">6×</div><div class="lbl">more buying customers per month</div>'
            '<div class="big">2.8×</div><div class="lbl">more revenue per month</div>'
            "Accessories and clothing launched on 28 Dec 2012. Customer numbers jumped far more than revenue: "
            "most new customers bought the new low-priced items, while bikes still bring in "
            "96.5% of all revenue."
            "</div>",
            unsafe_allow_html=True,
        )
        st.write("")

with st.expander("Monthly figures as a table"):
    st.dataframe(
        monthly.rename(columns={"order_month": "Month", "revenue": "Revenue", "customers": "Customers"}),
        hide_index=True, width="stretch",
        column_config={"Month": st.column_config.DateColumn(format="MMM YYYY"),
                       "Revenue": st.column_config.NumberColumn(format="%d")},
    )

source_footer("Source: gold.fact_sales joined to gold.dim_customers and gold.dim_products. "
              "Orders with an invalid date in the source (19 order lines) count in the totals but not in the monthly charts.")
