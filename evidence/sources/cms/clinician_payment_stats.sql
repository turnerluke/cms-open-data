-- Headline stats for the industry-payments dashboard. One row.
--
-- `dim_clinician_orphan_share` reports how much of the paid-NPI
-- population is missing from `dim_clinician`; the roster covers only
-- currently-enrolled Medicare clinicians while Sunshine reports on
-- every physician / dentist / advanced-practice provider a
-- manufacturer paid, so the gap is expected. Percentages are 0–1.
with npi_totals as (
    select
        covered_recipient_npi,
        sum(total_amount_of_payment_usd) as npi_dollars
    from main_marts.fct_industry_payments
    where covered_recipient_npi is not null
    group by 1
),
paid_npis as (
    select count(*) as paid_npis
    from npi_totals
),
orphans as (
    select count(*) as orphans
    from npi_totals as p
    left join main_marts.dim_clinician as d
        on p.covered_recipient_npi = d.npi
    where d.npi is null
)
select
    (select count(*) from main_marts.fct_industry_payments) as records,
    (select sum(total_amount_of_payment_usd)
     from main_marts.fct_industry_payments) as total_dollars,
    (select paid_npis from paid_npis) as paid_npis,
    (select count(distinct paying_manufacturer_or_gpo_id)
     from main_marts.fct_industry_payments) as paying_entities,
    (select max(payment_year)
     from main_marts.fct_industry_payments) as payment_year,
    cast((select orphans from orphans) as double)
        / (select paid_npis from paid_npis) as dim_clinician_orphan_share,
    cast(
        (select count(*) from main_marts.fct_industry_payments
         where nature_of_payment = 'Food and Beverage') as double
    ) / (select count(*) from main_marts.fct_industry_payments)
        as food_beverage_record_share,
    cast(
        (select sum(total_amount_of_payment_usd)
         from main_marts.fct_industry_payments
         where nature_of_payment = 'Food and Beverage') as double
    ) / (select sum(total_amount_of_payment_usd)
         from main_marts.fct_industry_payments)
        as food_beverage_dollar_share,
    (select max(as_of) from main_marts.fct_industry_payments) as as_of
