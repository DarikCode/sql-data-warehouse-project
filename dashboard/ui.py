"""
Layout building blocks shared by every page: the page header, KPI cards,
chart cards and the data-source footer. Keeping them here means every page
looks the same and the pages themselves only contain the analysis.
"""

import html
import re
from contextlib import contextmanager

import streamlit as st

CSS = """
<style>
:root {
  --ink: #0b0b0b;
  --ink-2: #52514e;
  --muted: #898781;
  --line: #e6e5df;
  --card: #ffffff;
  --page: #f4f4f1;
  --accent: #2a78d6;
  --good: #006300;
  --bad: #d03b3b;
}

/* page */
.stApp { background: var(--page); }
.block-container { padding-top: 1.6rem; padding-bottom: 3rem; max-width: 1320px; }
h1, h2, h3 { letter-spacing: -0.01em; }

/* sidebar */
section[data-testid="stSidebar"] { background: #ffffff; border-right: 1px solid var(--line); }
.brand { display: flex; gap: 10px; align-items: center; margin: 2px 0 18px; }
.brand-mark { width: 34px; height: 34px; border-radius: 9px; background: var(--accent);
              color: #fff; display: grid; place-items: center; font-weight: 700; font-size: 15px; }
.brand-name { font-weight: 650; color: var(--ink); font-size: 15px; line-height: 1.2; }
.brand-sub { color: var(--muted); font-size: 12px; }
.side-label { text-transform: uppercase; letter-spacing: .06em; font-size: 11px;
              color: var(--muted); font-weight: 600; margin: 6px 0 2px; }
.side-info { font-size: 12.5px; color: var(--ink-2); line-height: 1.6; }
.side-info b { color: var(--ink); font-weight: 600; }

/* page header */
.page-head { display: flex; justify-content: space-between; align-items: flex-end;
             gap: 16px; flex-wrap: wrap; margin-bottom: 18px; }
.eyebrow { text-transform: uppercase; letter-spacing: .08em; font-size: 11.5px;
           color: var(--accent); font-weight: 650; margin-bottom: 4px; }
.page-title { font-size: 30px; font-weight: 700; color: var(--ink); line-height: 1.15; }
.page-sub { color: var(--ink-2); font-size: 14.5px; margin-top: 6px; }
.chips { display: flex; gap: 6px; flex-wrap: wrap; margin-top: 10px; }
.chip { background: #ffffff; border: 1px solid var(--line); border-radius: 999px;
        padding: 2px 10px; font-size: 12px; color: var(--ink-2); }
.fresh { background: #ffffff; border: 1px solid var(--line); border-radius: 999px;
         padding: 5px 12px; font-size: 12.5px; color: var(--ink-2); white-space: nowrap; }
.dot { display: inline-block; width: 8px; height: 8px; border-radius: 50%;
       margin-right: 7px; vertical-align: 1px; }

/* KPI cards */
.kpi-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
            gap: 14px; margin-bottom: 14px; }
.kpi { background: var(--card); border: 1px solid var(--line); border-radius: 12px;
       padding: 14px 16px 13px; box-shadow: 0 1px 2px rgba(16, 24, 40, .04); }
.kpi-label { font-size: 12.5px; color: var(--ink-2); font-weight: 550; }
.kpi-value { font-size: 27px; font-weight: 680; color: var(--ink); margin-top: 4px;
             line-height: 1.15; }
.kpi-foot { font-size: 12px; color: var(--muted); margin-top: 6px; }
.up { color: var(--good); font-weight: 600; }
.down { color: var(--bad); font-weight: 600; }

/* chart cards */
[class*="st-key-card-"] { background: var(--card); border: 1px solid var(--line);
                          border-radius: 12px; padding: 16px 18px 6px;
                          box-shadow: 0 1px 2px rgba(16, 24, 40, .04); }
.card-title { font-size: 15px; font-weight: 650; color: var(--ink); }
.card-sub { font-size: 12.5px; color: var(--muted); margin-top: 2px; }
.card-note { font-size: 12px; color: var(--muted); margin: -4px 0 10px; }

/* insight card */
.insight { font-size: 13.5px; color: var(--ink-2); line-height: 1.6; }
.insight .big { font-size: 26px; font-weight: 700; color: var(--ink); line-height: 1.1; }
.insight .lbl { font-size: 12px; color: var(--muted); margin-bottom: 12px; }

/* footer */
.source { font-size: 12px; color: var(--muted); margin-top: 22px; padding-top: 12px;
          border-top: 1px solid var(--line); }
</style>
"""


def inject_css() -> None:
    st.markdown(CSS, unsafe_allow_html=True)


def _e(text) -> str:
    return html.escape(str(text))


def page_header(eyebrow: str, title: str, subtitle: str, chips: list[str] | None = None,
                fresh: str | None = None, fresh_ok: bool = True) -> None:
    chips_html = ""
    if chips:
        chips_html = '<div class="chips">' + "".join(f'<span class="chip">{_e(c)}</span>' for c in chips) + "</div>"
    fresh_html = ""
    if fresh:
        color = "#0ca30c" if fresh_ok else "#d03b3b"
        fresh_html = f'<div class="fresh"><span class="dot" style="background:{color}"></span>{_e(fresh)}</div>'
    st.markdown(
        f'<div class="page-head"><div><div class="eyebrow">{_e(eyebrow)}</div>'
        f'<div class="page-title">{_e(title)}</div><div class="page-sub">{_e(subtitle)}</div>'
        f"{chips_html}</div>{fresh_html}</div>",
        unsafe_allow_html=True,
    )


def kpi_row(items: list[dict]) -> None:
    """items: [{'label': ..., 'value': ..., 'foot': ..., 'delta': +0.18 (optional)}]"""
    cards = []
    for it in items:
        foot = _e(it.get("foot", ""))
        if it.get("delta") is not None:
            d = it["delta"]
            cls, arrow = ("up", "▲") if d >= 0 else ("down", "▼")
            foot = f'<span class="{cls}">{arrow} {abs(d):.0%}</span> {foot}'
        cards.append(
            f'<div class="kpi"><div class="kpi-label">{_e(it["label"])}</div>'
            f'<div class="kpi-value">{_e(it["value"])}</div><div class="kpi-foot">{foot}</div></div>'
        )
    st.markdown(f'<div class="kpi-grid">{"".join(cards)}</div>', unsafe_allow_html=True)


@contextmanager
def card(title: str, subtitle: str | None = None, note: str | None = None):
    """A white card with a title; put a chart or table inside the `with` block."""
    key = "card-" + re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")
    with st.container(key=key):
        head = f'<div class="card-title">{_e(title)}</div>'
        if subtitle:
            head += f'<div class="card-sub">{_e(subtitle)}</div>'
        st.markdown(head, unsafe_allow_html=True)
        yield
        if note:
            st.markdown(f'<div class="card-note">{_e(note)}</div>', unsafe_allow_html=True)


def source_footer(text: str) -> None:
    st.markdown(f'<div class="source">{_e(text)}</div>', unsafe_allow_html=True)
