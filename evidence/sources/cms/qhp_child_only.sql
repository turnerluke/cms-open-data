-- Child-only coverage availability across products.
-- HealthCare.gov requires medical issuers to allow child-only
-- enrollment; the dental market has a mix of adult-and-child plans,
-- dedicated child-only plans, and a smaller pool that omit child
-- enrollment entirely.

select
    product,
    coalesce(child_only_offering, 'Not offered') as child_only_offering,
    count(*) as plans
from main_marts.dim_qhp_plan
where market = 'individual'
group by 1, 2
order by 1, plans desc
