-- Top 20 promoted drug products (industry-payment `product_category
-- = 'Drug'`) by industry-payment dollars, joined to Part D
-- prescriber-billed spending on the same brand. Join is a strict
-- upper-cased brand-name match against
-- fct_prescriber_drug_spending (which is prescriber×brand×generic);
-- brands not sold under Medicare Part D (e.g. Comirnaty, Pluvicto)
-- surface as null Part D $, which is honest — those aren't Part D
-- drugs. Numbers are observational; a manufacturer paying $X to
-- promote a drug and clinicians writing $Y of prescriptions for it
-- are two independent, correlated snapshots.
with promo as (
    select
        product_name,
        sum(total_amount_of_payment_usd) as promo_dollars,
        count(distinct covered_recipient_npi) as promoted_clinicians,
        count(*) as promo_records
    from main_marts.fct_industry_payments
    where product_name is not null
        and product_category = 'Drug'
    group by 1
    order by promo_dollars desc
    limit 20
),
rx as (
    select
        upper(brand_name) as brand_upper,
        sum(total_drug_cost) as part_d_rx_dollars,
        count(distinct npi) as part_d_prescribers,
        sum(total_claims) as part_d_claims
    from main_marts.fct_prescriber_drug_spending
    group by 1
)
select
    p.product_name,
    p.promo_dollars,
    p.promoted_clinicians,
    p.promo_records,
    r.part_d_rx_dollars,
    r.part_d_prescribers,
    r.part_d_claims
from promo as p
left join rx as r on upper(p.product_name) = r.brand_upper
order by p.promo_dollars desc
