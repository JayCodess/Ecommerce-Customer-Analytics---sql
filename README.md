# Olist E-Commerce SQL Analytics

A portfolio project demonstrating SQL proficiency on the [Olist Brazilian E-Commerce Public Dataset](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) (~100K orders, Sep 2016 – Oct 2018). It progresses from beginner aggregations to advanced window-function analytics (cohort retention, RFM segmentation, CLV, churn detection), culminating in a fully optimized Streamlit dashboard powered by PostgreSQL views.

**Tech Stack:** PostgreSQL 18 (pure SQL, no PL/pgSQL) | Streamlit + Plotly | Hosted on Supabase

## Business Questions Answered

| # | Question | SQL File | Key Finding |
|---|----------|----------|-------------|
| 1 | What is total platform revenue? | `02_beginner.sql` | **~R$16M** across 99,441 orders |
| 2 | Which states drive the most volume? | `02_beginner.sql` | **São Paulo: 42%** of all orders — more than the next 3 states combined |
| 3 | Do higher-value orders get better reviews? | `03_intermediate.sql` | **No** — Premium orders (>R$500) average 3.88★ vs Low (<R$50) at 4.19★ |
| 4 | Which sellers are high-volume but low-quality? | `03_intermediate.sql` | **Only 6 sellers** with 50+ items and avg rating < 3.0 |
| 5 | How does cohort retention look? | `04_advanced.sql` | **< 1% at month 1** — typical marketplace one-time buyer pattern |
| 6 | What customer segments exist (RFM)? | `04_advanced.sql` | 16% Champions, 16% Loyal, 15% Can't Lose Them * |
| 7 | How many repeat customers have churned? | `04_advanced.sql` | **76.3%** of 2,997 repeat customers (dataset boundary effect) |
| 8 | How do late deliveries affect reviews? | `04_advanced.sql` | **4.30★ → 1.70★** — late >7 days is the strongest satisfaction predictor |

*\* RFM percentages are inflated by `NTILE(5)` on a frequency distribution dominated by one-time buyers. See `NOTES.md` #16.*

## Data Quality & Engineering Notes
Throughout the project, I documented 24 instances of data quality issues (e.g. embedded newlines in CSVs, duplicate IDs) and complex query solutions (e.g. Cartesian fan-outs, pooler timeouts). **[Read the full logs in NOTES.md](NOTES.md)**.

## How to Run

1. Clone the repo and place the Kaggle CSVs into a `data/` folder at the root.
2. Initialize the database and run the analysis:
```bash
psql -U postgres -c "CREATE DATABASE olist_ecommerce"
psql -U postgres -d olist_ecommerce -f sql/01_setup.sql
psql -U postgres -d olist_ecommerce -f sql/02_beginner.sql
psql -U postgres -d olist_ecommerce -f sql/03_intermediate.sql
psql -U postgres -d olist_ecommerce -f sql/04_advanced.sql
psql -U postgres -d olist_ecommerce -f sql/05_views.sql
```

## Live Dashboard

The dashboard visualizes the data purely by reading from `05_views.sql` — zero analytical logic is performed in Python.

> **Live Demo:** [https://dashboardsql.streamlit.app/](https://dashboardsql.streamlit.app/)

**Run locally:**
```bash
pip install -r dashboard/requirements.txt
# Copy secrets.toml.example to secrets.toml and add your database URL
streamlit run dashboard/app.py
```
