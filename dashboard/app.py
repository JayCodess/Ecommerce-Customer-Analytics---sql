"""
Olist E-Commerce Analytics Dashboard

Reads from SQL views in olist_ecommerce — zero analytical logic in Python.
All computation lives in sql/05_views.sql.
"""

import streamlit as st
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
from sqlalchemy import create_engine

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
st.set_page_config(
    page_title="Olist E-Commerce Analytics",
    page_icon="📊",
    layout="wide",
    initial_sidebar_state="collapsed",
)

try:
    DB_URL = st.secrets["db_url"]
except Exception:
    DB_URL = "postgresql://postgres@localhost:5432/olist_ecommerce"

COLORS = {
    "purple":  "#6C63FF",
    "cyan":    "#00D4AA",
    "pink":    "#FF6B9D",
    "amber":   "#FFB74D",
    "red":     "#EF5350",
    "blue":    "#42A5F5",
    "surface": "#1A1F2E",
    "text":    "#FAFAFA",
}

SEGMENT_COLORS = {
    "Champions":          "#6C63FF",
    "Loyal Customers":    "#42A5F5",
    "Potential Loyalists": "#00D4AA",
    "New Customers":      "#26C6DA",
    "Promising":          "#66BB6A",
    "Need Attention":     "#FFB74D",
    "About to Sleep":     "#FF8A65",
    "At Risk":            "#EF5350",
    "Can't Lose Them":    "#E91E63",
    "Hibernating":        "#78909C",
    "Lost":               "#546E7A",
    "Others":             "#9E9E9E",
}

PLOTLY_LAYOUT = dict(
    paper_bgcolor="rgba(0,0,0,0)",
    plot_bgcolor="rgba(0,0,0,0)",
    font=dict(family="Inter, sans-serif", color=COLORS["text"]),
    margin=dict(l=40, r=40, t=50, b=40),
)


# ---------------------------------------------------------------------------
# Data loading (cached) — queries push aggregation to the server so only
# small result sets travel over the Supabase SSL link.
# ---------------------------------------------------------------------------
@st.cache_resource
def get_engine():
    return create_engine(
        DB_URL,
        pool_pre_ping=True,
        pool_recycle=300,
        connect_args={
            "keepalives": 1,
            "keepalives_idle": 30,
            "keepalives_interval": 10,
            "keepalives_count": 5,
        },
    )


@st.cache_data(ttl=600)
def run_query(sql: str) -> pd.DataFrame:
    with get_engine().connect() as conn:
        return pd.read_sql(sql, conn)


def load_view(view_name: str) -> pd.DataFrame:
    """Small views only (cohort 225 rows, churn 3K, delivery 4)."""
    return run_query(f"SELECT * FROM olist.{view_name}")


# ---------------------------------------------------------------------------
# Metric card helper
# ---------------------------------------------------------------------------
def metric_row(metrics: list[tuple[str, str, str]]):
    """Render a row of styled metric cards. Each tuple: (label, value, icon)."""
    cols = st.columns(len(metrics))
    for col, (label, value, icon) in zip(cols, metrics):
        col.markdown(
            f"""
            <div style="background:#1A1F2E; border-radius:12px; padding:20px 24px;
                        border:1px solid #2A2F3E;">
                <div style="font-size:14px; color:#9E9E9E; margin-bottom:4px;">
                    {icon} {label}
                </div>
                <div style="font-size:28px; font-weight:700; color:#FAFAFA;">
                    {value}
                </div>
            </div>
            """,
            unsafe_allow_html=True,
        )


# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------
st.markdown(
    """
    <div style="text-align:center; padding:20px 0 10px 0;">
        <h1 style="font-size:2.2rem; font-weight:800; margin:0;
                    background: linear-gradient(135deg, #6C63FF, #00D4AA);
                    -webkit-background-clip: text; -webkit-text-fill-color: transparent;">
            Olist E-Commerce Analytics
        </h1>
        <p style="color:#9E9E9E; font-size:1rem; margin-top:6px;">
            ~100K orders · Brazilian marketplace · Sep 2016 – Oct 2018
        </p>
    </div>
    """,
    unsafe_allow_html=True,
)

# ---------------------------------------------------------------------------
# Tabs
# ---------------------------------------------------------------------------
tab1, tab2, tab3, tab4, tab5 = st.tabs([
    "📈 Cohort Retention",
    "🎯 RFM Segments",
    "💰 Customer LTV",
    "⚠️ Churn Risk",
    "🚚 Delivery Performance",
])


# ===== TAB 1: Cohort Retention =============================================
with tab1:
    df = load_view("v_cohort_retention")

    # Filter to cohorts with meaningful size and reasonable months_since
    df = df[df["cohort_size"] >= 50].copy()
    max_months = int(df["months_since"].max())

    st.markdown("#### Monthly Cohort Retention Heatmap")
    st.caption(
        "Each row is an acquisition cohort (month of first purchase). "
        "Cells show % of that cohort who placed another order N months later."
    )

    # Pivot for heatmap
    pivot = df.pivot_table(
        index="cohort_month",
        columns="months_since",
        values="retention_rate",
        aggfunc="first",
    ).fillna(0)

    # Format index as YYYY-MM
    pivot.index = pd.to_datetime(pivot.index).strftime("%Y-%m")
    pivot.columns = [f"M{int(c)}" for c in pivot.columns]

    fig = go.Figure(data=go.Heatmap(
        z=pivot.values,
        x=pivot.columns,
        y=pivot.index,
        colorscale=[
            [0, "#0E1117"],
            [0.01, "#1A1F3E"],
            [0.05, "#2E3A6E"],
            [0.2, "#4A54A0"],
            [0.5, "#6C63FF"],
            [1.0, "#A594FF"],
        ],
        text=pivot.values.round(1).astype(str),
        texttemplate="%{text}%",
        textfont=dict(size=10),
        hovertemplate="Cohort: %{y}<br>Month: %{x}<br>Retention: %{z:.1f}%<extra></extra>",
        colorbar=dict(title="%", ticksuffix="%"),
    ))
    fig.update_layout(
        **PLOTLY_LAYOUT,
        height=max(400, len(pivot) * 22),
        xaxis_title="Months Since Acquisition",
        yaxis_title="Cohort",
        yaxis=dict(autorange="reversed"),
    )
    st.plotly_chart(fig, use_container_width=True)

    # Metrics
    cohort_sizes = df[df["months_since"] == 0]
    m1 = df[df["months_since"] == 1]
    avg_m1 = m1["retention_rate"].mean() if len(m1) > 0 else 0

    metric_row([
        ("Total Cohorts", str(len(cohort_sizes)), "📅"),
        ("Avg Cohort Size", f"{cohort_sizes['cohort_size'].mean():,.0f}", "👥"),
        ("Avg M1 Retention", f"{avg_m1:.1f}%", "🔄"),
        ("Max Months Tracked", str(max_months), "📏"),
    ])


# ===== TAB 2: RFM Segments =================================================
with tab2:
    # Server-side aggregation — avoids pulling 96K rows over Supabase
    seg_counts = run_query("""
        SELECT segment,
               COUNT(*)          AS count,
               ROUND(AVG(monetary), 0) AS avg_monetary
        FROM olist.v_rfm_segments
        GROUP BY segment
        ORDER BY count
    """)

    rfm_totals = run_query("""
        SELECT COUNT(*)                     AS total,
               ROUND(AVG(monetary), 0)      AS avg_monetary
        FROM olist.v_rfm_segments
    """)

    st.markdown("#### Customer Segmentation (RFM)")
    st.caption(
        "Recency × Frequency × Monetary scored 1–5 via NTILE(5). "
        "Segment labels follow standard RFM literature."
    )

    fig = go.Figure()
    fig.add_trace(go.Bar(
        y=seg_counts["segment"],
        x=seg_counts["count"],
        orientation="h",
        marker_color=[SEGMENT_COLORS.get(s, "#9E9E9E") for s in seg_counts["segment"]],
        text=seg_counts["count"].apply(lambda x: f"{x:,}"),
        textposition="outside",
        hovertemplate="%{y}: %{x:,} customers<extra></extra>",
    ))
    fig.update_layout(
        **PLOTLY_LAYOUT,
        height=400,
        xaxis_title="Number of Customers",
        yaxis_title="",
        showlegend=False,
    )
    st.plotly_chart(fig, use_container_width=True)

    # Metrics
    total_cust = int(rfm_totals["total"].iloc[0])
    champ_count = int(seg_counts.loc[seg_counts["segment"] == "Champions", "count"].sum())
    risk_count = int(seg_counts.loc[
        seg_counts["segment"].isin(["At Risk", "Hibernating", "About to Sleep"]), "count"
    ].sum())
    avg_mon = float(rfm_totals["avg_monetary"].iloc[0])

    metric_row([
        ("Total Customers", f"{total_cust:,}", "👤"),
        ("Champions", f"{champ_count:,}", "🏆"),
        ("At Risk + Hibernating", f"{risk_count:,}", "⚠️"),
        ("Avg Monetary", f"R${avg_mon:,.0f}", "💵"),
    ])

    # Scatter: server-side sample of 5000 rows (not 96K)
    st.markdown("#### Recency vs. Monetary by Segment")
    sample = run_query("""
        SELECT recency_days, frequency, monetary,
               r_score, f_score, m_score, segment
        FROM olist.v_rfm_segments
        ORDER BY RANDOM()
        LIMIT 5000
    """)
    fig2 = px.scatter(
        sample,
        x="recency_days",
        y="monetary",
        color="segment",
        color_discrete_map=SEGMENT_COLORS,
        opacity=0.6,
        hover_data=["frequency", "r_score", "f_score", "m_score"],
        labels={"recency_days": "Recency (days)", "monetary": "Monetary (R$)"},
    )
    fig2.update_layout(**PLOTLY_LAYOUT, height=500, legend=dict(
        orientation="h", yanchor="bottom", y=-0.3, xanchor="center", x=0.5,
        font=dict(size=11),
    ))
    fig2.update_traces(marker=dict(size=5))
    st.plotly_chart(fig2, use_container_width=True)


# ===== TAB 3: Customer LTV =================================================
with tab3:
    st.markdown("#### Customer Lifetime Value Distribution")
    st.caption("Running cumulative revenue per customer, ordered by purchase date.")

    # Server-side: binned histogram via width_bucket (~50 rows, not 96K)
    clv_bins = run_query("""
        WITH final_clv AS (
            SELECT DISTINCT ON (customer_unique_id) cumulative_revenue
            FROM olist.v_clv
            ORDER BY customer_unique_id, order_sequence DESC
        ),
        bounds AS (
            SELECT MIN(cumulative_revenue) AS lo, MAX(cumulative_revenue) AS hi
            FROM final_clv
        )
        SELECT
            width_bucket(cumulative_revenue, lo, hi + 0.01, 50) AS bucket,
            ROUND(lo + (width_bucket(cumulative_revenue, lo, hi + 0.01, 50) - 1)
                  * ((hi - lo) / 50), 0)                        AS bin_lo,
            ROUND(lo + width_bucket(cumulative_revenue, lo, hi + 0.01, 50)
                  * ((hi - lo) / 50), 0)                        AS bin_hi,
            COUNT(*)                                             AS customers
        FROM final_clv CROSS JOIN bounds
        GROUP BY bucket, lo, hi
        ORDER BY bucket
    """)

    # Server-side: summary stats (1 row)
    clv_stats = run_query("""
        WITH final_clv AS (
            SELECT DISTINCT ON (customer_unique_id)
                   cumulative_revenue, order_sequence
            FROM olist.v_clv
            ORDER BY customer_unique_id, order_sequence DESC
        )
        SELECT
            ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY cumulative_revenue)::NUMERIC, 0) AS median,
            ROUND(AVG(cumulative_revenue)::NUMERIC, 0)  AS mean,
            ROUND(MAX(cumulative_revenue)::NUMERIC, 0)  AS max,
            COUNT(*) FILTER (WHERE order_sequence > 1) AS multi_order
        FROM final_clv
    """)

    # Server-side: top 20 (20 rows)
    top20 = run_query("""
        WITH final_clv AS (
            SELECT DISTINCT ON (customer_unique_id)
                   customer_unique_id, order_sequence, cumulative_revenue
            FROM olist.v_clv
            ORDER BY customer_unique_id, order_sequence DESC
        )
        SELECT customer_unique_id, order_sequence, cumulative_revenue
        FROM final_clv
        ORDER BY cumulative_revenue DESC
        LIMIT 20
    """)

    # Histogram from pre-binned data
    fig = go.Figure()
    fig.add_trace(go.Bar(
        x=clv_bins["bin_lo"],
        y=clv_bins["customers"],
        width=(clv_bins["bin_hi"] - clv_bins["bin_lo"]) * 0.95,
        marker_color=COLORS["purple"],
        hovertemplate="R$%{x:,.0f}: %{y:,} customers<extra></extra>",
    ))
    fig.update_layout(
        **PLOTLY_LAYOUT,
        height=400,
        xaxis_title="Lifetime Revenue (R$)",
        yaxis_title="Number of Customers",
        bargap=0.05,
    )
    st.plotly_chart(fig, use_container_width=True)

    # Metrics
    stats = clv_stats.iloc[0]
    metric_row([
        ("Median LTV", f"R${stats['median']:,.0f}", "📊"),
        ("Mean LTV", f"R${stats['mean']:,.0f}", "📈"),
        ("Max LTV", f"R${stats['max']:,.0f}", "🔝"),
        ("Multi-Order Customers", f"{int(stats['multi_order']):,}", "🔄"),
    ])

    # Top 20 table
    st.markdown("#### Top 20 Customers by Lifetime Value")
    top20.index = range(1, len(top20) + 1)
    top20.columns = ["Customer ID", "Orders", "Lifetime Revenue (R$)"]
    top20["Lifetime Revenue (R$)"] = top20["Lifetime Revenue (R$)"].apply(
        lambda x: f"R${x:,.2f}"
    )
    st.dataframe(top20, use_container_width=True, height=400)


# ===== TAB 4: Churn Risk ===================================================
with tab4:
    df = load_view("v_churn_risk")

    st.markdown("#### Churn Risk Assessment")
    st.caption(
        "Customers with 2+ orders. Churned = days since last order > "
        "1.5× personal average purchase cadence."
    )

    churned = df[df["is_churned"] == True]
    active = df[df["is_churned"] == False]

    # Metrics
    metric_row([
        ("Repeat Customers", f"{len(df):,}", "👥"),
        ("Active", f"{len(active):,} ({len(active)*100/len(df):.0f}%)", "✅"),
        ("Churned", f"{len(churned):,} ({len(churned)*100/len(df):.0f}%)", "🚨"),
        ("Avg Cadence (days)", f"{df['avg_days_between'].mean():.0f}", "📅"),
    ])

    # Donut chart
    col1, col2 = st.columns([1, 2])
    with col1:
        fig = go.Figure(data=[go.Pie(
            labels=["Active", "Churned"],
            values=[len(active), len(churned)],
            hole=0.65,
            marker_colors=[COLORS["cyan"], COLORS["red"]],
            textinfo="label+percent",
            textfont=dict(size=14),
            hovertemplate="%{label}: %{value:,} customers (%{percent})<extra></extra>",
        )])
        fig.update_layout(**PLOTLY_LAYOUT, height=350, showlegend=False)
        st.plotly_chart(fig, use_container_width=True)

    with col2:
        # Distribution of days_since_last
        fig2 = px.histogram(
            df,
            x="days_since_last",
            color="is_churned",
            nbins=50,
            labels={
                "days_since_last": "Days Since Last Order",
                "is_churned": "Churned",
            },
            color_discrete_map={True: COLORS["red"], False: COLORS["cyan"]},
            barmode="overlay",
            opacity=0.7,
        )
        fig2.update_layout(**PLOTLY_LAYOUT, height=350, yaxis_title="Customers")
        st.plotly_chart(fig2, use_container_width=True)

    # Filterable table
    st.markdown("#### Customer Detail")
    status_filter = st.selectbox(
        "Filter by status", ["All", "Active only", "Churned only"]
    )
    if status_filter == "Active only":
        show_df = active
    elif status_filter == "Churned only":
        show_df = churned
    else:
        show_df = df

    st.dataframe(
        show_df.sort_values("days_since_last", ascending=False).head(200),
        use_container_width=True,
        height=400,
    )


# ===== TAB 5: Delivery Performance =========================================
with tab5:
    df = load_view("v_delivery_performance")

    st.markdown("#### Delivery Timeliness vs. Customer Satisfaction")
    st.caption(
        "Delta = actual delivery date − estimated delivery date. "
        "Negative = early. Delivered orders only."
    )

    # Ensure ordering
    bucket_order = ["Early", "On-Time", "Late (1–7 days)", "Late (>7 days)"]
    df["delivery_bucket"] = pd.Categorical(
        df["delivery_bucket"], categories=bucket_order, ordered=True
    )
    df = df.sort_values("delivery_bucket")

    # Metrics
    total_orders = df["order_count"].sum()
    early_pct = df.loc[df["delivery_bucket"] == "Early", "pct_of_total"].values
    early_pct = early_pct[0] if len(early_pct) > 0 else 0
    late_gt7 = df.loc[df["delivery_bucket"] == "Late (>7 days)"]
    late_review = late_gt7["avg_review_score"].values[0] if len(late_gt7) > 0 else 0

    metric_row([
        ("Delivered Orders", f"{total_orders:,}", "📦"),
        ("Early Deliveries", f"{early_pct}%", "🟢"),
        ("Late >7 Days Avg Rating", f"{late_review}★", "🔴"),
        ("Avg Delta (Early)", f"{df.loc[df['delivery_bucket']=='Early', 'avg_delta_days'].values[0]} days", "⏱️"),
    ])

    # Dual-axis: bar for order count, line for avg review
    col1, col2 = st.columns(2)

    with col1:
        fig = go.Figure()
        fig.add_trace(go.Bar(
            x=df["delivery_bucket"],
            y=df["order_count"],
            marker_color=[COLORS["cyan"], COLORS["blue"], COLORS["amber"], COLORS["red"]],
            text=df["order_count"].apply(lambda x: f"{x:,}"),
            textposition="outside",
            hovertemplate="%{x}: %{y:,} orders<extra></extra>",
        ))
        fig.update_layout(
            **PLOTLY_LAYOUT,
            height=400,
            title="Order Count by Delivery Bucket",
            yaxis_title="Orders",
            xaxis_title="",
            showlegend=False,
        )
        st.plotly_chart(fig, use_container_width=True)

    with col2:
        fig2 = go.Figure()
        fig2.add_trace(go.Bar(
            x=df["delivery_bucket"],
            y=df["avg_review_score"],
            marker_color=[COLORS["cyan"], COLORS["blue"], COLORS["amber"], COLORS["red"]],
            text=df["avg_review_score"].apply(lambda x: f"{x:.2f}★"),
            textposition="outside",
            hovertemplate="%{x}: %{y:.2f}★ avg<extra></extra>",
        ))
        fig2.update_layout(
            **PLOTLY_LAYOUT,
            height=400,
            title="Avg Review Score by Delivery Bucket",
            yaxis_title="Avg Review Score",
            yaxis_range=[0, 5],
            xaxis_title="",
            showlegend=False,
        )
        st.plotly_chart(fig2, use_container_width=True)


# ---------------------------------------------------------------------------
# Footer
# ---------------------------------------------------------------------------
st.markdown("---")
st.markdown(
    """
    <div style="text-align:center; color:#546E7A; font-size:0.85rem; padding:10px 0;">
        Built with SQL views → Streamlit + Plotly · All analytics computed in PostgreSQL
    </div>
    """,
    unsafe_allow_html=True,
)
