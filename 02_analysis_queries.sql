-- =========================================================
-- d2c analytics -- analysis queries (sql server / t-sql)
-- runs against orders_clean / customers_clean from
-- 01_cleaning_views.sql
-- =========================================================

use d2c_project;
go

-- ---------------------------------------------------------
-- 1. monthly revenue trend
-- ---------------------------------------------------------
-- finding: revenue grows steadily through 2024-2025, then
-- tapers in early-mid 2026 -- this is right-censoring (no new
-- signups near the dataset's end date), not a business decline.
-- ---------------------------------------------------------
select
    format(order_date, 'yyyy-MM') as order_month,
    sum(gross_revenue) as total_revenue,
    count(*) as order_count
from orders_clean
where is_bad_quantity = 0
group by format(order_date, 'yyyy-MM')
order by order_month;


-- ---------------------------------------------------------
-- 2. month-over-month growth (window function: lag)
-- ---------------------------------------------------------
-- finding: march consistently shows the strongest monthly
-- growth both years, matching the end-of-financial-year sale
-- effect.
-- ---------------------------------------------------------
with monthly_revenue as (
    select
        format(order_date, 'yyyy-MM') as order_month,
        sum(gross_revenue) as total_revenue
    from orders_clean
    where is_bad_quantity = 0
    group by format(order_date, 'yyyy-MM')
)
select
    order_month,
    total_revenue,
    lag(total_revenue) over (order by order_month) as previous_month_revenue,
    round(
        (total_revenue - lag(total_revenue) over (order by order_month))
        / lag(total_revenue) over (order by order_month) * 100, 1
    ) as mom_growth_pct
from monthly_revenue
order by order_month;


-- ---------------------------------------------------------
-- 3. category-level seasonality (window function: lag + partition by)
-- ---------------------------------------------------------
-- the first version filtered down to just sep/oct/nov BEFORE
-- calculating lag(), which meant "previous month" sometimes
-- skipped 9 months (comparing nov 2024 to sep 2025 as if they
-- were adjacent rows). the fix: calculate lag() across the full,
-- unfiltered monthly series first (in one cte), then filter down
-- to the months of interest afterward (in a second step).
-- lesson: filter after window functions calculate, not before,
-- unless the filtered set is specifically what should define
-- "previous row".
-- ---------------------------------------------------------
with monthly_category_revenue as (
    select
        format(order_date, 'yyyy-MM') as order_month,
        category,
        sum(gross_revenue) as total_revenue
    from orders_clean
    where is_bad_quantity = 0
    group by format(order_date, 'yyyy-MM'), category
),
with_growth as (
    select
        order_month,
        category,
        total_revenue,
        lag(total_revenue) over (partition by category order by order_month) as previous_month_revenue,
        round(
            (total_revenue - lag(total_revenue) over (partition by category order by order_month))
            / lag(total_revenue) over (partition by category order by order_month) * 100, 1
        ) as mom_growth_pct
    from monthly_category_revenue
)
select *
from with_growth
where order_month in ('2024-09','2024-10','2024-11','2025-09','2025-10','2025-11')
order by category, order_month;

-- month-over-month % at the category level turned out too noisy
-- (each category-month only has 20-60 orders), so the approach
-- below replaces it -- comparing festive vs non-festive average
-- order volume and discount depth directly, across many more
-- orders per bucket.

with tagged as (
    select
        order_date,
        category,
        gross_revenue,
        discount_pct,
        case
            when (month(order_date) = 10 and day(order_date) >= 10)
              or (month(order_date) = 11 and day(order_date) <= 15)
                then 'Festive'
            else 'Non-Festive'
        end as period_type
    from orders_clean
    where is_bad_quantity = 0
),
period_days as (
    select period_type, count(distinct order_date) as day_count
    from tagged
    group by period_type
)
select
    t.category,
    t.period_type,
    count(*) as order_count,
    pd.day_count,
    round(count(*) * 1.0 / pd.day_count, 2) as orders_per_day,
    round(avg(t.gross_revenue), 0) as avg_order_value,
    round(avg(t.discount_pct), 1) as avg_discount_pct
from tagged t
join period_days pd on t.period_type = pd.period_type
group by t.category, t.period_type, pd.day_count
order by t.category, t.period_type;

-- finding: festive season drives a modest 15-30% increase in
-- daily order volume broadly across all categories, but makeup,
-- skincare, and apparel show a much sharper jump in average
-- discount depth (~10% to 25%+) during the same window -- a
-- margin-vs-volume tradeoff not visible from revenue totals alone.


-- ---------------------------------------------------------
-- 4. top products per category (window function: rank)
-- ---------------------------------------------------------
-- rank() within each category, rather than overall, so a cheap
-- personal care item isn't unfairly compared to an expensive
-- fragrance item.
-- ---------------------------------------------------------
with product_revenue as (
    select
        category,
        product_id,
        sum(gross_revenue) as total_revenue,
        count(*) as order_count
    from orders_clean
    where is_bad_quantity = 0
    group by category, product_id
),
ranked as (
    select
        category,
        product_id,
        total_revenue,
        order_count,
        rank() over (partition by category order by total_revenue desc) as revenue_rank
    from product_revenue
)
select *
from ranked
where revenue_rank <= 3
order by category, revenue_rank;


-- ---------------------------------------------------------
-- 5. repeat customer rate (window functions: row_number, lag)
-- ---------------------------------------------------------
-- row_number() numbers each customer's own orders in time order,
-- so you can tell instantly whether an order was someone's first
-- purchase or a repeat.
-- ---------------------------------------------------------
with customer_orders as (
    select
        customer_id,
        order_date,
        row_number() over (partition by customer_id order by order_date) as order_sequence
    from orders_clean
    where customer_id is not null
      and is_bad_quantity = 0
)
select
    count(distinct customer_id) as total_customers_with_orders,
    count(distinct case when order_sequence >= 2 then customer_id end) as repeat_customers,
    round(
        count(distinct case when order_sequence >= 2 then customer_id end) * 100.0
        / count(distinct customer_id), 1
    ) as repeat_customer_rate_pct
from customer_orders;

-- finding: 67.5% repeat rate -- higher than a realistic 20-35%
-- d2c benchmark. honest explanation: the synthetic "one-time
-- buyer" archetype's underlying statistical distribution still
-- allowed occasional repeat orders by chance.


-- ---------------------------------------------------------
-- 6. average days between orders (window function: lag)
-- ---------------------------------------------------------
-- this number becomes the basis for the churn threshold used
-- later in python (roughly 2x the average gap).
-- ---------------------------------------------------------
with customer_gaps as (
    select
        customer_id,
        order_date,
        datediff(day, lag(order_date) over (partition by customer_id order by order_date), order_date) as days_since_last_order
    from orders_clean
    where customer_id is not null
      and is_bad_quantity = 0
)
select
    round(avg(cast(days_since_last_order as float)), 1) as avg_days_between_orders,
    min(days_since_last_order) as min_gap,
    max(days_since_last_order) as max_gap
from customer_gaps
where days_since_last_order is not null;

-- finding: 104.9 days average -> churn threshold set at 210 days
-- (roughly 2x) in the python phase.
