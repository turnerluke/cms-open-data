-- Bin the prescribing population (fct_prescriber_drug_spending, one
-- row per NPI × drug) by industry-payment dollars, then report mean
-- and median prescriber-billed drug cost per bin. Prescribers with
-- zero payments form their own bin; the rest are decile-split by
-- payment $. Observational only — no causal claim.
--
-- fct_prescriber_drug_spending is a single snapshot with no year
-- column; fct_industry_payments covers program year 2024. The 642k
-- NPI overlap is the sole join key.
with payments as (
    select
        covered_recipient_npi as npi,
        sum(total_amount_of_payment_usd) as pay_dollars
    from main_marts.fct_industry_payments
    where covered_recipient_npi is not null
    group by 1
),
scripts as (
    select
        npi,
        sum(total_drug_cost) as rx_dollars,
        sum(total_claims) as rx_claims
    from main_marts.fct_prescriber_drug_spending
    group by 1
),
joined as (
    select
        s.npi,
        coalesce(p.pay_dollars, 0) as pay_dollars,
        s.rx_dollars,
        s.rx_claims
    from scripts as s
    left join payments as p on s.npi = p.npi
),
binned as (
    select
        pay_dollars,
        rx_dollars,
        rx_claims,
        case
            when pay_dollars = 0 then 0
            else ntile(10) over (
                partition by (case when pay_dollars = 0 then 0 else 1 end)
                order by pay_dollars
            )
        end as pay_bin
    from joined
)
select
    case
        when pay_bin = 0 then 'No payments'
        else 'Decile ' || cast(pay_bin as varchar)
    end as bin,
    pay_bin,
    count(*) as prescribers,
    avg(pay_dollars) as avg_pay_dollars,
    median(pay_dollars) as median_pay_dollars,
    avg(rx_dollars) as avg_rx_dollars,
    median(rx_dollars) as median_rx_dollars,
    avg(rx_claims) as avg_rx_claims
from binned
group by pay_bin
order by pay_bin
