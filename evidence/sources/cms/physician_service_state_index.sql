-- State payment index: sum(state avg payment × state services) vs the
-- same services priced at the national average payment. A value >1
-- means the state pays above national on its service mix; <1 means
-- below. Restricted to the 50 states + DC (2-digit FIPS codes,
-- excluding 9x pseudo-codes and territory codes 60/66/69/72/78) so a
-- handful of Armed Forces / territory buckets don't crowd the chart.
--
-- The five state rows CMS emitted with NULL geography_code are also
-- filtered out here (`geography_code is not null`).
select
    geography_code,
    geography_description,
    sum(total_services) as state_services,
    sum(total_services * avg_medicare_payment_amount)
        as state_payment,
    sum(total_services * national_avg_medicare_payment_amount)
        as expected_at_national,
    sum(total_services * avg_medicare_payment_amount)
    / nullif(
        sum(total_services * national_avg_medicare_payment_amount), 0
    ) as payment_index
from main_marts.fct_physician_service_geography
where
    geography_level = 'State'
    and geography_code is not null
    and length(geography_code) = 2
    and geography_code not like '9%'
    and geography_code not in ('60', '66', '69', '72', '78')
group by geography_code, geography_description
order by payment_index desc
