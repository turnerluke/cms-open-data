-- Concentration of industry-payment dollars across paid clinicians.
-- Two views of the same distribution:
--   * top_share = share of $ going to the top-N% of NPIs by $
--   * bracket_clinicians / bracket_dollars = clinicians and $ falling
--     inside each per-clinician total bracket
-- A single row per bracket keeps the source ≤ ~15 rows.
with npi_totals as (
    select
        covered_recipient_npi,
        sum(total_amount_of_payment_usd) as npi_dollars
    from main_marts.fct_industry_payments
    where covered_recipient_npi is not null
    group by 1
),
overall as (
    select
        sum(npi_dollars) as grand_total,
        count(*) as paid_npis
    from npi_totals
),
percentiles as (
    select
        npi_dollars,
        ntile(1000) over (order by npi_dollars desc) as milli
    from npi_totals
),
top_shares as (
    select
        'Top 0.1%' as bucket, 1 as sort_key,
        sum(case when milli = 1 then npi_dollars end)
            / sum(npi_dollars) as top_share,
        count(case when milli = 1 then 1 end) as clinicians
    from percentiles
    union all
    select
        'Top 1%', 2,
        sum(case when milli <= 10 then npi_dollars end)
            / sum(npi_dollars),
        count(case when milli <= 10 then 1 end)
    from percentiles
    union all
    select
        'Top 10%', 3,
        sum(case when milli <= 100 then npi_dollars end)
            / sum(npi_dollars),
        count(case when milli <= 100 then 1 end)
    from percentiles
    union all
    select
        'Top 50%', 4,
        sum(case when milli <= 500 then npi_dollars end)
            / sum(npi_dollars),
        count(case when milli <= 500 then 1 end)
    from percentiles
    union all
    select
        'All paid clinicians', 5,
        1.0,
        count(*)
    from percentiles
)
select
    bucket,
    top_share,
    clinicians
from top_shares
order by sort_key
