# NOTES — Data Quality, Surprises & Decisions

Running log of non-obvious findings. Each entry: what, why, what I did.

---

## Phase 1 — Database Setup

**1. Reviews CSV row count mismatch (104,720 lines vs 99,224 records)**
The `review_comment_message` field contains embedded newlines inside quoted strings (5,495 extra line breaks total). Naïve line-counting gives a wrong "expected" count. PostgreSQL's `\COPY ... CSV` parser handles this correctly — no action needed, but don't trust `wc -l` or PowerShell `Measure-Object -Line` for record counts on this file. Use Python's `csv.reader` or trust the `COPY` output.

**2. Duplicate review_id values (814 duplicates out of 99,224 rows)**
The raw Olist CSV ships with ~814 rows sharing a `review_id` with another row. This is a known data quality issue in the public dataset, not a loading bug. Chose **Option B (relax constraint)**: surrogate `SERIAL` PK (`review_pk`), non-unique index on `review_id`. Simpler than deduplication and preserves all rows without data loss.

**3. customer_id vs customer_unique_id**
Olist generates a fresh `customer_id` per order, so the same person gets a different `customer_id` each time they buy. `customer_unique_id` is the stable person-level key. All customer-level analysis (retention, CLV, RFM, churn) must join through `customer_unique_id` or repeat-purchase metrics will read as zero. Added an index on `customer_unique_id` for fast lookups.

**4. Column name typos in source data**
`product_name_lenght` and `product_description_lenght` are misspelled in the original CSV (should be "length"). Preserved the original spelling in the schema to avoid confusion during `\COPY` — renaming would require column aliasing at load time for no real benefit.

---

## Phase 2 — Beginner SQL

**5. Total revenue: ~R$16M across 99,441 orders**
Revenue sourced from `order_payments.payment_value` (not `order_items.price`) because payments capture what was actually charged, including freight. Some `payment_value` entries are 0.00 — these appear to be voucher-offset payments where the voucher covered the full amount.

**6. São Paulo dominates: 42% of all orders**
SP alone has 41,746 orders — more than the next 3 states combined (RJ + MG + RS = ~30K). Any per-state analysis is heavily SP-skewed; worth noting when interpreting state-level metrics.

**7. 97.2% of orders are delivered**
Order status distribution: 96,478 delivered, 1,107 shipped, 625 canceled. Only 5 orders in "created" status and 2 "approved" — likely incomplete data at the edges of the collection window (Sep 2016 and Oct 2018).

**8. Reviews are heavily 5-star skewed (57.8%)**
Average review score is 4.09, but the distribution is bimodal: 57.8% are 5-star and 11.5% are 1-star, with very few 2-star (3.2%). Median would be more representative than mean for this distribution.

**9. Sparse data at timeline edges**
Sep 2016 has only 4 orders, Oct 2018 has only 4. The dataset's usable range is roughly Oct 2016 – Aug 2018. Dec 2016 has just 1 order (likely a gap in data collection). Cohort/trend analyses should filter to the clean window or at least note the edge sparsity.

**10. Top payment (R$13,664.08) is legit but disputed**
Investigated the highest single payment: 8× identical fixed-telephony devices at R$1,680 each, ordered from Rio de Janeiro. Paid in full on credit card. Marked "delivered" but the customer left a 1-star review: "we didn't receive it." Real B2B-style bulk purchase with a delivery dispute — not a data anomaly.

---

## Phase 3 — Intermediate SQL

**11. Higher-value orders get slightly worse reviews**
Order value tiers show a clear negative correlation with review scores: Low (<R$50) averages 4.19★, Medium (R$50–200) 4.10★, High (R$200–500) 3.98★, Premium (>R$500) 3.88★. This ~0.3-star drop from bottom to top tier is consistent — higher expectations or longer shipping times for bulkier/pricier items likely drive it.

**12. Only 6 sellers are high-volume AND low-rated**
Out of all sellers with 50+ items sold, only 6 have an average review below 3.0. The worst (seller `1ca7...`) has 136 items across 114 orders with a 2.20★ average and R$13K revenue — enough volume and revenue to be a marketplace risk. The dataset's seller quality is remarkably consistent overall.

**13. Star Sellers dominate the qualifying pool (68%)**
Among sellers with 30+ items sold (683 total), 465 (68%) qualify as "Star Sellers" (avg rating ≥ 4.0 and deliveries ahead of schedule). Only 6 (0.9%) are "Underperformers." The platform's delivery-ahead-of-estimate pattern (global avg delta = −11.4 days) inflates the Star tier — Olist's estimated delivery dates appear intentionally conservative. Note: the −11.4 figure is an average of per-seller averages (not a raw per-order average) and only includes orders with `order_status = 'delivered'`. Cf. entry #18's −12.9, which is the straight per-order average — both are correct but answer different questions (seller-level vs. order-level).

**14. Q1 JOIN fan-out: reviews × order_items produces duplicates**
The 5-table join in Q1 joins order_reviews on order_id, but an order with 3 items and 1 review produces 3 rows (one per item, each with the same review_score). This is correct for item-level analysis but would overcount reviews if naively aggregated. The composition query (Q5) handles this by aggregating at the seller level, which absorbs the fan-out correctly.

---

## Phase 4 — Advanced SQL

**15. Repeat-purchase retention is extremely low (~0.3–0.6% at month 1)**
Cohort retention rates drop to under 1% by month 1 across all cohorts. E.g., the Jan 2017 cohort (764 customers) retains only 3 (0.39%) at month 1. This is characteristic of marketplace datasets where `customer_unique_id` tracks one-time buyers — most Olist customers make a single purchase. This isn't necessarily alarming for a marketplace model, but it does mean the "retention" metric here measures cross-purchase loyalty, not session-level engagement.

**16. RFM segmentation: 43% Loyal + 16% Champions, but driven by NTILE quirk**
The RFM scoring produces 41,452 "Loyal Customers" (43.1%) and 15,574 "Champions" (16.2%). This looks inflated because NTILE(5) on a heavily skewed frequency distribution (most customers have exactly 1 order) assigns equal-sized buckets regardless of actual value spread — a customer with 1 order can get f_score=3 or higher simply by being in the top 60% of a mostly-1-order population. The segments are technically correct per the scoring rules but should be interpreted with this caveat.

**17. 76.3% of repeat customers are flagged as churned**
Of 2,997 customers with 2+ orders (the only ones where churn detection is meaningful), 2,287 (76.3%) exceed their personal 1.5× cadence threshold. This is expected: the dataset ends Oct 2018, and most repeat customers' last orders predate that by months. The churn flag is a snapshot-in-time metric, not a prediction — it's most useful for identifying the 710 "Active" customers who were still purchasing near the dataset boundary.

**18. Late deliveries obliterate review scores: 4.30★ → 1.70★**
Delivery performance shows a dramatic satisfaction cliff: Early deliveries (90.4% of orders) average 4.30★, On-Time 4.10★, Late by 1–7 days 2.71★, and Late by >7 days 1.70★. The ~1.6-star drop between "Early" and "Late >7 days" is the strongest single predictor of review scores in the dataset. Olist's conservative delivery estimates (avg delta −12.9 days early, computed per-order) appear deliberate to protect satisfaction scores. Cf. entry #13's −11.4, which is an average of per-seller averages — slightly less negative because high-volume sellers dilute toward the mean.

**19. 90.4% of deliveries arrive early — confirming padded estimates**
Only 6.8% of delivered orders arrive on-time or late. This reinforces NOTES #13: Olist systematically overestimates delivery times. The 2,878 orders that arrive >7 days late (3.0%) are the ones that truly damage satisfaction, suggesting a bimodal delivery failure mode rather than a gradual degradation.

---

## Phase 6 — Streamlit Dashboard

**20. Views as the single source of truth**
Five SQL views (`olist.v_cohort_retention`, `v_clv`, `v_rfm_segments`, `v_churn_risk`, `v_delivery_performance`) wrap the Phase 4 queries. The Streamlit app reads via `SELECT * FROM olist.v_<name>` — zero analytical logic in Python. This means the dashboard always reflects the exact same numbers as the raw SQL, and any future query fix propagates automatically.

**21. Supabase SSL disconnect on large views — `SELECT *` is the enemy**
After switching from local Postgres to Supabase (PgBouncer transaction pooler, port 6543), `SELECT * FROM olist.v_rfm_segments` (96K rows) and `v_clv` (~99K rows) both failed with `SSL connection has been closed unexpectedly`. Root cause: PgBouncer's aggressive connection timeout kills the SSL socket mid-transfer when the result set takes too long to stream. First attempted fix — `pool_pre_ping`, `pool_recycle`, and TCP keepalives in `create_engine()` — had no effect because the connection wasn't idle; it was actively transferring data when killed. The real fix was pushing aggregation to the server:
- **RFM**: replaced `SELECT *` (96K rows) with three queries: `GROUP BY segment` (~8 rows), `COUNT/AVG` (1 row), and `ORDER BY RANDOM() LIMIT 5000` (scatter sample).
- **CLV**: replaced `DISTINCT ON` (96K rows) with `width_bucket()` histogram (~50 rows), `PERCENTILE_CONT/AVG/MAX` summary (1 row), and `ORDER BY cumulative_revenue DESC LIMIT 20` (top 20 table).
- Cohort (225 rows), churn (3K rows), and delivery (4 rows) were already small enough to survive the pooler.

**22. ROUND(double precision, integer) does not exist in Postgres**
After the server-side aggregation fix, the CLV stats query failed with `function round(double precision, integer) does not exist`. Postgres's `ROUND(val, precision)` overload only accepts `NUMERIC`, not `double precision`. `PERCENTILE_CONT()` returns `double precision`, and `AVG()`/`MAX()` on a `NUMERIC(10,2)` column return `NUMERIC` normally but return `double precision` when the input comes through a view with window functions. Fix: explicit `::NUMERIC` casts before `ROUND()`. This is a recurring Postgres gotcha — `ROUND(x)` (no precision) works on any numeric type, but `ROUND(x, n)` requires `NUMERIC`.
