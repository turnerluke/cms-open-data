-- Top dialysis chains by facility count, with the chain-averaged
-- five-star rating. CMS labels non-chain facilities with the literal
-- chain value 'Independent', so the table sums to the dialysis
-- population without any synthesized bucket.
select
    chain_organization as chain,
    count(*) as facilities,
    sum(number_of_dialysis_stations) as stations,
    avg(five_star::double) as avg_stars,
    count(five_star) as rated_facilities
from main_marts.dim_dialysis_facility
group by 1
order by facilities desc
