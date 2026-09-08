-- Per-clinician-total distribution: how many paid NPIs fall into
-- each dollar bracket, and what share of total $ they account for.
-- The tallies expose the long-tailed shape without leaking any
-- per-NPI grain.
with npi_totals as (
    select
        covered_recipient_npi,
        sum(total_amount_of_payment_usd) as npi_dollars
    from main_marts.fct_industry_payments
    where covered_recipient_npi is not null
    group by 1
),
labeled as (
    select
        npi_dollars,
        case
            when npi_dollars < 100 then 1
            when npi_dollars < 1000 then 2
            when npi_dollars < 10000 then 3
            when npi_dollars < 100000 then 4
            when npi_dollars < 1000000 then 5
            else 6
        end as bracket_sort,
        case
            when npi_dollars < 100 then '< $100'
            when npi_dollars < 1000 then '$100 – $1k'
            when npi_dollars < 10000 then '$1k – $10k'
            when npi_dollars < 100000 then '$10k – $100k'
            when npi_dollars < 1000000 then '$100k – $1M'
            else '$1M+'
        end as bracket
    from npi_totals
),
grand as (
    select sum(npi_dollars) as grand_total from labeled
)
select
    l.bracket,
    count(*) as clinicians,
    sum(l.npi_dollars) as dollars,
    sum(l.npi_dollars) / g.grand_total as dollar_share
from labeled as l
cross join grand as g
group by l.bracket, l.bracket_sort, g.grand_total
order by l.bracket_sort
