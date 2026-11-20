"""Pipeline health: is the data fresh, did the last run work, how long does it take?

Reads the run log the pipeline writes to etl.pipeline_runs and etl.step_log.
"""

import plotly.graph_objects as go
import streamlit as st

from charts import CONFIG, CRITICAL, SERIES, TEMPLATE, hbar
from data import WarehouseUnavailable, load_runs, load_steps
from ui import card, kpi_row, page_header, source_footer

try:
    runs = load_runs()
    steps = load_steps()
except WarehouseUnavailable as exc:
    st.error(f"Can't read the run log: {exc}")
    st.stop()

if runs.empty:
    page_header("Engineering", "Pipeline health", "Monitoring of the load pipeline.")
    st.info("No pipeline runs logged yet. Run `.\\run_pipeline.ps1` first.")
    st.stop()

last = runs.iloc[-1]
last_steps = steps[steps["run_id"] == last["run_id"]]
ok_runs = runs[runs["status"] == "success"]
last_ok = last["status"] == "success"

page_header("Engineering", "Pipeline health",
            "Every run of run_pipeline.ps1: did it work, how long did it take, did the data change?",
            fresh=f"Last run #{last['run_id']}: {'succeeded' if last_ok else last['status']}",
            fresh_ok=last_ok)

# ---------------- Latest run ----------------
finished_at = last["finished_at"]
kpi_row([
    {"label": "Last run", "value": f"#{last['run_id']}",
     "foot": finished_at.strftime("finished %d %b %Y, %H:%M") if finished_at is not None else "still running"},
    {"label": "Status", "value": "✓ Success" if last_ok else ("✕ Failed" if last["status"] == "failed" else last["status"]),
     "foot": f"{len(last_steps[last_steps['status'] == 'success'])} of {len(last_steps)} steps succeeded"},
    {"label": "Duration", "value": f"{last['duration_ms'] / 1000:.1f} s" if last["duration_ms"] else "—",
     "foot": f"median of all runs {runs['duration_ms'].median() / 1000:.1f} s"},
    {"label": "Success rate", "value": f"{len(ok_runs) / len(runs):.0%}", "foot": f"{len(ok_runs)} of {len(runs)} runs"},
])

if last["status"] == "failed":
    failed = last_steps[last_steps["status"] == "failed"]
    if not failed.empty:
        st.error(f"**Step `{failed.iloc[0]['step_name']}` failed:**\n\n{failed.iloc[0]['message']}",
                 icon=":material/error:")

# ---------------- Rows per layer: did a load suddenly deliver less? ----------------
loads = steps[steps["rows_in_layer"].notna() & (steps["status"] == "success")]
layer_cards = []
for step_name, layer, source in [("bronze_load", "Bronze rows", "raw CSV data"),
                                 ("silver_load", "Silver rows", "after cleaning"),
                                 ("gold_refresh", "Gold rows", "star schema")]:
    history = loads[loads["step_name"] == step_name]["rows_in_layer"].astype(int).tolist()
    if not history:
        layer_cards.append({"label": layer, "value": "—", "foot": source})
        continue
    change = history[-1] - history[-2] if len(history) > 1 else 0
    foot = f"{source} · " + ("no change vs previous run" if change == 0 else f"{change:+,} vs previous run")
    layer_cards.append({"label": layer, "value": f"{history[-1]:,}", "foot": foot})
kpi_row(layer_cards)

left, right = st.columns(2, gap="medium")
with left:
    timed = last_steps.dropna(subset=["duration_ms"])
    with card(f"Step durations, run #{last['run_id']}", "Milliseconds per step"):
        st.plotly_chart(
            hbar(timed["step_name"], timed["duration_ms"], "Duration (ms)",
                 value_text=[f"{v:,.0f} ms" for v in timed["duration_ms"]], height=260),
            width="stretch", config=CONFIG, theme=None,
        )
with right:
    finished = runs.dropna(subset=["duration_ms"])
    is_failed = finished["status"] == "failed"
    fig = go.Figure(go.Bar(
        x=finished["run_id"].astype(str), y=finished["duration_ms"] / 1000,
        marker=dict(color=[CRITICAL if f else SERIES[0] for f in is_failed], line=dict(width=0)),
        text=["Failed" if f else "" for f in is_failed], textposition="outside", cliponaxis=False,
        textfont=dict(color=CRITICAL, size=12),
        customdata=finished["status"],
        hovertemplate="<b>Run #%{x}</b><br>%{customdata}<br>%{y:.1f} s<extra></extra>",
    ))
    fig.update_layout(template=TEMPLATE, height=260, showlegend=False,
                      xaxis=dict(title="Run", type="category"), yaxis=dict(title="Seconds"))
    with card("Duration of every run", "Failed runs stop early and are marked in red"):
        st.plotly_chart(fig, width="stretch", config=CONFIG, theme=None)

# ---------------- Run history ----------------
table_status = {"success": "✅ Success", "failed": "❌ Failed", "running": "⏳ Running"}
history = runs.sort_values("run_id", ascending=False).copy()
first_failure = steps[steps["status"] == "failed"].drop_duplicates("run_id").set_index("run_id")["step_name"]
history["failed_step"] = history["run_id"].map(first_failure).fillna("")
history["status"] = history["status"].map(lambda s: table_status.get(s, s))
with card("Run history", "Newest first"):
    st.dataframe(
        history[["run_id", "status", "started_at", "duration_ms", "failed_step", "rebuild", "run_by"]].rename(columns={
            "run_id": "Run", "status": "Status", "started_at": "Started", "duration_ms": "Duration (ms)",
            "failed_step": "Failed step", "rebuild": "Rebuild", "run_by": "Run by",
        }),
        hide_index=True, width="stretch",
        column_config={"Started": st.column_config.DatetimeColumn(format="DD MMM YYYY, HH:mm:ss")},
    )
    st.write("")

with st.expander("All steps of every run"):
    st.dataframe(steps.sort_values(["run_id", "step_order"], ascending=[False, True]),
                 hide_index=True, width="stretch")

source_footer("Source: etl.pipeline_runs and etl.step_log, written by run_pipeline.ps1. Not affected by the sidebar filters.")
