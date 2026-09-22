# Olist E-Commerce SQL Analytics

A portfolio project demonstrating SQL proficiency — beginner through advanced — on the [Olist Brazilian E-Commerce Public Dataset](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) (~100K orders, Sep 2016 – Oct 2018).

Each SQL file builds on the previous, progressing from simple aggregates to multi-table JOINs to window-function-driven customer analytics (cohort retention, RFM segmentation, CLV, churn detection).

---

## Business Questions Answered

| # | Question | SQL File | Key Finding |
|---|----------|----------|-------------|
| 1 | What is total platform revenue? | `02_beginner.sql` | **~R$16M** across 99,441 orders |
| 2 | Which states drive the most volume? | `02_beginner.sql` | **São Paulo: 42%** of all orders — more than the next 3 states combined |
| 3 | Do higher-value orders get better reviews? | `03_intermediate.sql` | **No** — Premium orders (>R$500) average 3.88★ vs Low (<R$50) at 4.19★ |
| 4 | Which sellers are high-volume but low-quality? | `03_intermediate.sql` | **Only 6 sellers** with 50+ items and avg rating < 3.0 |
| 5 | How does cohort retention look? | `04_advanced.sql` | **< 1% at month 1** — typical marketplace one-time buyer pattern |
| 6 | What customer segments exist (RFM)? | `04_advanced.sql` | 43% Loyal, 16% Champions, 12% Hibernating * |
| 7 | How many repeat customers have churned? | `04_advanced.sql` | **76.3%** of 2,997 repeat customers (dataset boundary effect) |
| 8 | How do late deliveries affect reviews? | `04_advanced.sql` | **4.30★ → 1.70★** — late >7 days is the strongest satisfaction predictor |

\* RFM percentages are inflated by `NTILE(5)` on a frequency distribution dominated by one-time buyers — a customer with 1 order can score f≥3 simply by being in the top 60% of a mostly-single-purchase population. See `NOTES.md` #16.

---

## SQL File Guide

### [`sql/01_setup.sql`](sql/01_setup.sql) — Phase 1: Database Setup
Creates the `olist_ecommerce` database, `olist` schema, all 8 tables with proper types/constraints, loads data from CSVs via `\COPY`, and validates row counts. Handles the 814 duplicate `review_id` values via a surrogate `SERIAL` PK.

### [`sql/02_beginner.sql`](sql/02_beginner.sql) — Phase 2: Beginner SQL
12 queries demonstrating `SUM`, `COUNT`, `AVG`, `MIN`, `MAX`, `GROUP BY`, `WHERE`, `ILIKE`, `ORDER BY`/`LIMIT`, `DATE_TRUNC`, and a window function for percentage-of-total.

### [`sql/03_intermediate.sql`](sql/03_intermediate.sql) — Phase 3: Intermediate SQL
5 queries demonstrating multi-table `JOIN`s (3–5 tables), `GROUP BY` + `HAVING`, CTEs with scalar subqueries, `CASE`-based bucketing, and a composition query combining all techniques into a seller performance dashboard.

### [`sql/04_advanced.sql`](sql/04_advanced.sql) — Phase 4: Advanced SQL
5 analytical queries:
1. **Cohort Retention** — CTE-based, with year×12+month arithmetic (avoids the `AGE()` year-wrap bug)
2. **Customer Lifetime Value** — Running cumulative revenue via `SUM() OVER (ROWS UNBOUNDED PRECEDING)`
3. **RFM Segmentation** — `NTILE(5)` scoring → 8 customer segments via exhaustive `CASE`
4. **Churn Detection** — `LAG()`-based personal cadence with 1.5× threshold (≥ 2 orders only)
5. **Delivery Performance** — Estimated vs. actual delivery bucketing, cross-referenced with review scores

---

## Key Modeling Decision: `customer_unique_id`

Olist generates a fresh `customer_id` per order — the same person gets a different `customer_id` each time they buy. `customer_unique_id` is the stable person-level key.

**All customer-level analysis** (retention, CLV, RFM, churn) joins through `customer_unique_id`. Without this, repeat-purchase metrics read as zero. This is documented in `NOTES.md` entry #3 and referenced throughout the SQL files.

---

## Notable Data Quality Findings

These are the highlights — the full running log with 19 entries lives in [`NOTES.md`](NOTES.md).

- **Review CSV line count mismatch**: 104,720 lines but only 99,224 records — 5,495 embedded newlines in quoted `review_comment_message` fields. PostgreSQL's CSV parser handles this correctly; naïve line-counting does not.
- **814 duplicate `review_id` values**: Known Olist data quality issue. Handled with a surrogate `SERIAL` PK instead of deduplication to preserve all rows.
- **Sparse data at timeline edges**: Sep 2016 (4 orders), Dec 2016 (1 order), Oct 2018 (4 orders). Usable window is ~Oct 2016 – Aug 2018.
- **Olist pads delivery estimates**: 90.4% of orders arrive early (avg −12.9 days per-order). This is deliberate — late deliveries crater review scores from 4.30★ to 1.70★.

---

## How to Run

### Prerequisites
- PostgreSQL (tested on 18.4)
- The [Olist dataset](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) CSVs in a `data/` folder at the project root

### Setup
```bash
# 1. Create the database
psql -U postgres -c "CREATE DATABASE olist_ecommerce"

# 2. Run the setup script (creates schema, tables, loads data, validates)
psql -U postgres -d olist_ecommerce -f sql/01_setup.sql

# 3. Run the query files
psql -U postgres -d olist_ecommerce -f sql/02_beginner.sql
psql -U postgres -d olist_ecommerce -f sql/03_intermediate.sql
psql -U postgres -d olist_ecommerce -f sql/04_advanced.sql
```

### Data Files (not in repo)
The `data/` directory is `.gitignore`'d. Download the dataset from Kaggle and extract the CSVs there:
```
data/
├── olist_customers_dataset.csv
├── olist_order_items_dataset.csv
├── olist_order_payments_dataset.csv
├── olist_order_reviews_dataset.csv
├── olist_orders_dataset.csv
├── olist_products_dataset.csv
├── olist_sellers_dataset.csv
└── product_category_name_translation.csv
```

---

## Project Structure

```
├── sql/
│   ├── 01_setup.sql            # Database + schema + data loading
│   ├── 02_beginner.sql         # 12 beginner queries
│   ├── 03_intermediate.sql     # 5 intermediate queries
│   └── 04_advanced.sql         # 5 advanced analytical queries
├── data/                       # CSVs (gitignored)
├── NOTES.md                    # Running data quality log (19 entries)
├── README.md                   # This file
└── .gitignore
```

---

## Tech Stack

| Component | Tool |
|-----------|------|
| Database | PostgreSQL 18 |
| Language | SQL (PL/pgSQL-free — pure standard SQL + Postgres extensions) |
| Dataset | [Olist Brazilian E-Commerce](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) (~100K orders, 8 tables) |

---

> **🚧 Coming next** — Phases 6–7: Streamlit dashboard (interactive charts from SQL views) and Tableau Public workbook.
