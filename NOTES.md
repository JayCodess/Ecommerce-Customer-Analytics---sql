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
