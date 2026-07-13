# D2C Growth & Churn Intelligence Platform

## Project Overview

An end-to-end analytics project examining customer behavior for a simulated Indian D2C (direct-to-consumer) retail business — covering data cleaning, RFM segmentation, cohort retention, churn modeling, and a published Power BI dashboard. The project traces the full pipeline a real analytics team would run: from raw, deliberately messy transactional data through to stakeholder-ready insights.

## Business Problem

D2C brands live and die by retention economics, not just top-line sales. Rising ad costs mean acquiring a new customer is expensive, so the real question isn't "how much did we sell" — it's "who are our best customers, which ones are quietly leaving, and does seasonal demand actually behave the way we assume it does?" This project answers all three using SQL, Python, and Power BI on a purpose-built dataset.

## Dataset

- **Source:** Synthetic, generated in Python to simulate a realistic Indian D2C retail business — customer archetypes (loyal repeat buyers, discount hunters, one-time buyers, seasonal shoppers), real Indian retail seasonality (Diwali, Republic Day sales, monsoon, End-of-Financial-Year), and deliberately injected data quality issues.
- **orders** — 12,000+ transactions
- **customers** — 6,000+ records
- **Coverage:** January 2024 – June 2026

## Tools Used

- **SQL Server** — Data cleaning and quality checks, exploratory and business-focused analysis (2 scripts, CTEs and window functions)
- **Python** (Pandas, NumPy, Matplotlib, Seaborn) — RFM segmentation, cohort retention analysis, churn scoring
- **Power BI** — 4-page interactive dashboard

## Approach

### 1. Data Cleaning (SQL Server)
- Fixed a legacy `text` column type blocking joins between orders and products
- Parsed order dates stored in two mixed formats (`YYYY-MM-DD` and `DD-MM-YYYY`) into a single clean date column
- Standardized inconsistent category naming (casing, whitespace, missing spaces) against a canonical category list
- Flagged — rather than deleted — guest checkouts, duplicate signups, quantity errors, and price outliers, so downstream analysis can decide whether to include or exclude them

### 2. SQL Analysis
Six analytical query sets covering:
- Monthly revenue trend and month-over-month growth (window functions: `LAG`)
- Category-level seasonality — festive season vs. non-festive order volume and discount depth
- Top 3 revenue-driving products per category (`RANK`, `PARTITION BY`)
- Repeat customer rate (`ROW_NUMBER`)
- Average days between orders, used later to set a data-driven churn threshold

### 3. Python Analysis
- **RFM Segmentation** — Recency, Frequency, and Monetary scores (quantile-based), combined into 6 business segments (Champions, Loyal Customers, At Risk, Needs Attention, New Customers, Lost)
- **Cohort Retention** — customers grouped by signup month, tracking active-customer retention over time
- **Churn Scoring** — a 210-day inactivity threshold (derived from the average reorder gap found in SQL), validated against RFM segments

### 4. Power BI Dashboard (4 pages)
- **Title** — project overview
- **Executive Summary** — headline KPIs, monthly revenue trend, revenue by category
- **Customer Segmentation** — RFM segment breakdown, churn rate by segment, cohort retention heatmap
- **Seasonality & Discounting** — festive vs. non-festive order volume and discount depth by category

Every page includes a written insights panel — the takeaway a stakeholder should walk away with, not just the raw chart.

## Key Findings

**Revenue growth is real, and its apparent 2026 decline isn't**
Revenue grew steadily through 2024–2025 as the customer base expanded, then tapered in early-mid 2026. This isn't a business decline — it's right-censoring: the dataset's time window ends before recent signup cohorts have had time to accumulate orders.

**March consistently drives the strongest growth of the year**
Both 2024 and 2025 show their sharpest month-over-month revenue growth in March, matching the End-of-Financial-Year sale effect — a repeatable, plannable seasonal pattern rather than a one-off spike.

**Festive season affects volume and discounting differently**
Diwali-window order volume rises a modest 15–30% broadly across every category — but Makeup, Skincare, and Apparel show a far sharper jump in average discount depth (roughly 10% to 25%+) during the same window. Aggregate revenue alone hides this; it only surfaces once volume and discounting are examined separately, revealing a real margin-vs-volume tradeoff.

**The customer base is nearly split between its best and most disengaged customers**
RFM segmentation found 22% of customers are "Champions" (recent, frequent, high-value) while 21.5% are fully "Lost" — a near-even split that gives a clear, quantified target for retention investment in the "At Risk" and "Needs Attention" segments sitting between them.

**Retention decays fast, and the churn threshold holds up under validation**
Month-0 cohort retention averages 35–40%, decaying to single digits by month 5–6 — typical of D2C repeat-purchase behavior. A 210-day churn threshold (roughly 2x the observed average reorder gap) was validated directly against the RFM segments: Champions show ~4% churn versus ~100% for Lost, At Risk, and Needs Attention, confirming both measures agree.

## Files in This Repository

| File | Description |
|---|---|
| `01_cleaning_views.sql` | Data quality profiling queries and the `orders_clean` / `customers_clean` SQL views |
| `02_analysis_queries.sql` | CTEs and window-function queries for revenue trends, seasonality, and RFM inputs |
| `d2c_analysis.ipynb` | Python notebook — RFM segmentation, cohort retention, churn scoring |
| `D2C Analysis.pbix` | Power BI dashboard file |
| `ExecutiveSummary.png` | Dashboard page 2 |
| `CustomerSegmentation.png` | Dashboard page 3 |
| `Seasonality&Discounting.png` | Dashboard page 4 |

## Notes on the Process

Several real data issues were deliberately built into the dataset and caught during the cleaning and analysis phases — including a legacy `text` column type breaking SQL joins, a filtering-order bug in a window-function query that produced impossible month-over-month growth percentages, a missing CSV header row that silently dropped the first record on import into Python, and an incorrect cohort-size denominator that produced retention values over 100%. Each was diagnosed, explained, and fixed as part of the analysis — a closer reflection of real analyst work than a project where everything works on the first try.
