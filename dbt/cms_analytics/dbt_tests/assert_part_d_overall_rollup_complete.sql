-- Downstream consumers (marts, Evidence pages) count each Part D drug
-- once by filtering to `is_manufacturer_rollup`; a drug-year published
-- only as per-manufacturer rows would silently vanish from them.
select
    brand_name,
    generic_name,
    spending_year
from {{ ref('fct_part_d_drug_spending') }}
group by 1, 2, 3
having count(case when is_manufacturer_rollup then 1 end) = 0
