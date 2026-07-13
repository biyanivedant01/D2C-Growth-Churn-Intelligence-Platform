-- =========================================================
-- d2c analytics -- cleaning layer (sql server / t-sql)
-- builds orders_clean and customers_clean views on top of the
-- raw tables loaded via ssms's import flat file wizard.
-- nothing is deleted here -- issues are fixed where possible,
-- and flagged where they need a judgment call later.
-- =========================================================

use d2c_project;
go

-- ---------------------------------------------------------
-- step 0 -- fix source column types
-- ---------------------------------------------------------
-- both orders_raw.product_id and products_raw.product_id were
-- imported as the legacy `text` type, which sql server cannot
-- directly compare with `=`. this breaks any join between the
-- two tables. fix: convert both to varchar.
-- ---------------------------------------------------------

alter table orders_raw alter column product_id varchar(20);
alter table products_raw alter column product_id varchar(20);


-- ---------------------------------------------------------
-- step 1 -- data quality profiling (run these first to see
-- the issues yourself before building the fixes)
-- ---------------------------------------------------------

-- nulls / guest checkout
select 
    count(*) as total_orders,
    sum(case when customer_id is null or customer_id = '' then 1 else 0 end) as missing_customer_id
from orders_raw;

select 
    count(*) as total_customers,
    sum(case when acquisition_channel is null or acquisition_channel = '' then 1 else 0 end) as missing_channel
from customers_raw;

-- duplicate customers (note: exact-id duplicates return 0 rows on purpose --
-- the injected duplicates use a different id with a _dup suffix, not a
-- repeated id. that's why the _dup pattern check below is the real signal.)
select customer_id, count(*) as cnt
from customers_raw
group by customer_id
having count(*) > 1;

select count(*) from customers_raw where customer_id like '%_DUP';

-- order_date format inconsistency
select top 20 order_id, order_date
from orders_raw
where order_date not like '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]';

-- messy category text
select distinct category
from orders_raw
order by category;

-- quantity / price outliers
select count(*) from orders_raw where quantity <= 0;

select
    count(*) as total_orders,
    sum(case when quantity <= 0 then 1 else 0 end) as bad_quantity_count,
    sum(case when unit_price > p.price * 5 then 1 else 0 end) as price_outlier_count,
    sum(case when customer_id is null or customer_id = '' then 1 else 0 end) as guest_checkout_count
from orders_raw o
join products_raw p on o.product_id = p.product_id;


-- ---------------------------------------------------------
-- step 2 -- orders_clean
-- ---------------------------------------------------------
-- fixes/flags applied:
--   1. order_date: mixed formats (yyyy-mm-dd and dd-mm-yyyy)
--      parsed into a real date column using pattern matching.
--   2. category: inconsistent casing/whitespace/spacing
--      standardized by normalizing both sides (uppercase, no
--      spaces) and matching against a canonical list of 8 categories.
--   3. quantity <= 0, price > 5x list price, and missing
--      customer_id are flagged, not deleted -- downstream
--      analyses decide whether to include or exclude them.
-- ---------------------------------------------------------

if object_id('orders_clean', 'v') is not null drop view orders_clean;
go

create view orders_clean as
select
    o.order_id,
    nullif(o.customer_id, '') as customer_id,
    case when o.customer_id is null or o.customer_id = '' then 1 else 0 end as is_guest_checkout,

    case
        when o.order_date like '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
            then try_convert(date, o.order_date, 23)   -- yyyy-mm-dd
        when o.order_date like '[0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9]'
            then try_convert(date, o.order_date, 105)  -- dd-mm-yyyy
        else null
    end as order_date,

    o.product_id,
    c.correct_category as category,

    o.quantity,
    case when o.quantity <= 0 then 1 else 0 end as is_bad_quantity,

    o.unit_price,
    p.price as list_price,
    case when o.unit_price > p.price * 5 then 1 else 0 end as is_price_outlier,

    o.discount_pct,
    o.gross_revenue,
    o.acquisition_channel

from orders_raw o
join products_raw p
    on o.product_id = p.product_id
left join (
    values
        ('Skincare'), ('Haircare'), ('Makeup'), ('Fragrance'),
        ('Personal Care'), ('Wellness'), ('Apparel'), ('Rainwear')
) as c(correct_category)
    on upper(replace(o.category, ' ', '')) = upper(replace(c.correct_category, ' ', ''));
go

-- verified: select count(*) from orders_clean;  -> 12032 (matches orders_raw exactly)


-- ---------------------------------------------------------
-- step 3 -- customers_clean
-- ---------------------------------------------------------
-- _dup customers flagged rather than merged automatically --
-- deciding which record is canonical is a judgment call left
-- for the analysis stage, not something to silently delete.
-- ---------------------------------------------------------

if object_id('customers_clean', 'v') is not null drop view customers_clean;
go

create view customers_clean as
select
    customer_id,
    case when customer_id like '%\_DUP' escape '\' then 1 else 0 end as is_duplicate_signup,
    nullif(acquisition_channel, '') as acquisition_channel,
    city,
    signup_date
from customers_raw;
go

-- verified: select count(*), sum(is_duplicate_signup) from customers_clean;
--           -> total 6090, duplicates 90


-- ---------------------------------------------------------
-- final sanity check -- run both together
-- ---------------------------------------------------------
select
    (select count(*) from orders_clean) as orders_clean_rows,
    (select count(*) from customers_clean) as customers_clean_rows,
    (select sum(is_guest_checkout) from orders_clean) as guest_orders,
    (select sum(is_bad_quantity) from orders_clean) as bad_quantity_orders,
    (select sum(is_price_outlier) from orders_clean) as price_outlier_orders,
    (select sum(is_duplicate_signup) from customers_clean) as duplicate_signups;
