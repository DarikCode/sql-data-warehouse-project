"""
Shared chart styling, so every chart in the dashboard looks the same.

Design rules followed:
- One color per series, taken in a fixed order (never by rank), from a
  colorblind-checked palette. A single-series chart uses slot 1 only.
- Thin marks, hairline gridlines, muted axes: the data is the loudest
  thing on the chart.
- Hover tooltips on every chart; no number printed on every point.
- One y-axis per chart. Two measures on different scales get two charts.
- Chart titles live in the card around the chart, not inside the plot.
"""

import plotly.graph_objects as go

# Categorical palette (fixed order). Slots 1-3 are validated as a set.
SERIES = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300", "#6250d6", "#e34948"]
CRITICAL = "#d03b3b"  # status color: failures only, always next to a text label

SURFACE = "#ffffff"
INK = "#0b0b0b"
INK_2 = "#52514e"
MUTED = "#898781"
GRID = "#ecebe6"
AXIS = "#c3c2b7"

FONT = 'system-ui, -apple-system, "Segoe UI", sans-serif'

TEMPLATE = go.layout.Template(
    layout=dict(
        font=dict(family=FONT, color=INK_2, size=12.5),
        paper_bgcolor=SURFACE,
        plot_bgcolor=SURFACE,
        colorway=SERIES,
        margin=dict(l=8, r=12, t=12, b=8),
        # automargin: grow the margins so tick labels are never clipped
        xaxis=dict(showgrid=False, linecolor=AXIS, ticks="outside", tickcolor=AXIS, ticklen=4,
                   automargin=True,
                   tickfont=dict(color=MUTED), title=dict(font=dict(color=MUTED, size=12))),
        yaxis=dict(gridcolor=GRID, gridwidth=1, zeroline=False, showline=False, automargin=True,
                   tickformat="~s",
                   tickfont=dict(color=MUTED), title=dict(font=dict(color=MUTED, size=12))),
        hoverlabel=dict(bgcolor=SURFACE, bordercolor=GRID, font=dict(color=INK, family=FONT, size=12.5)),
        legend=dict(orientation="h", x=0, y=1.02, yanchor="bottom", font=dict(color=INK_2)),
        bargap=0.35,
        barcornerradius=4,
    )
)

CONFIG = {"displayModeBar": False}  # pass to st.plotly_chart(config=CONFIG)


def fmt_number(value: float) -> str:
    """29356250 -> '29.4M', 7075 -> '7.1K'."""
    value = float(value)
    for limit, suffix in ((1e9, "B"), (1e6, "M"), (1e3, "K")):
        if abs(value) >= limit:
            return f"{value / limit:.1f}{suffix}"
    return f"{value:,.0f}"


def line(x, y, hover_label: str, color: str = SERIES[0], height: int = 300) -> go.Figure:
    fig = go.Figure(go.Scatter(
        x=x, y=y, mode="lines",
        line=dict(color=color, width=2),
        fill="tozeroy", fillcolor="rgba(42,120,214,0.06)",
        hovertemplate=f"<b>%{{x|%b %Y}}</b><br>{hover_label}: %{{y:,.0f}}<extra></extra>",
    ))
    fig.update_layout(template=TEMPLATE, hovermode="x unified", height=height, showlegend=False,
                      yaxis=dict(rangemode="tozero"))
    return fig


def hbar(labels, values, hover_label: str, value_text=None, color: str = SERIES[0],
         height: int | None = None, colors=None, room: float = 1.32) -> go.Figure:
    """Horizontal bars, first row on top. value_text: optional label at the bar end."""
    fig = go.Figure(go.Bar(
        x=values, y=labels, orientation="h",
        marker=dict(color=colors if colors is not None else color, line=dict(width=0)),
        text=value_text, textposition="outside", cliponaxis=False,
        textfont=dict(color=INK_2, size=12),
        hovertemplate=f"<b>%{{y}}</b><br>{hover_label}: %{{x:,.0f}}<extra></extra>",
    ))
    fig.update_layout(
        template=TEMPLATE, showlegend=False,
        height=height or max(180, 40 * len(labels) + 50),
        yaxis=dict(autorange="reversed", showgrid=False, tickformat="", automargin=True,
                   tickfont=dict(color=INK_2, size=12.5), ticksuffix="  "),
        xaxis=dict(showgrid=True, gridcolor=GRID, showline=False, ticks="", tickformat="~s",
                   showticklabels=value_text is None),
    )
    if value_text is not None and len(values):
        # leave room at the right so the end labels are never cut off
        fig.update_xaxes(range=[0, float(max(values)) * room])
    return fig


def vbar(labels, values, hover_label: str, color: str = SERIES[0], value_text=None,
         height: int = 300) -> go.Figure:
    fig = go.Figure(go.Bar(
        x=labels, y=values,
        marker=dict(color=color, line=dict(width=0)),
        text=value_text, textposition="outside", cliponaxis=False, textfont=dict(color=INK_2, size=12),
        hovertemplate=f"<b>%{{x}}</b><br>{hover_label}: %{{y:,.0f}}<extra></extra>",
    ))
    fig.update_layout(template=TEMPLATE, showlegend=False, height=height)
    if value_text is not None and len(values):
        fig.update_yaxes(range=[0, float(max(values)) * 1.18])
    return fig
