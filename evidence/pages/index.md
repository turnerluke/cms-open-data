---
title: CMS Open Data
---

Dashboards over the mart layer of the
[cms-open-data](https://github.com/turnerluke/cms-open-data) warehouse:
Medicare drug spending (Parts B and D) and hospital quality, modeled
with dbt on DuckDB from CMS public datasets.

## Pages

- [Drug spending](/drug-spending) — top drugs, multi-year trends, and a
  Part B vs Part D comparison for drugs billed in both programs.
- [Hospital quality](/hospital-quality) — overall star ratings,
  healthcare-associated infection performance, HRRP excess
  readmission ratios by condition and state, and VBP total
  performance scores with domain decomposition.
- [Cost vs quality](/cost-vs-quality) — Medicare inpatient payment per
  discharge by star rating, with case mix as the confounder.
- [Prescribers](/prescribers) — who drives spending on the top Part D
  drugs: specialties, top-1% concentration, and billed-vs-gross cost.
- [Nursing homes](/nursing-homes) — star ratings, ownership, quality
  measures, and health-inspection enforcement for certified nursing
  homes.
- [Home health and hospice](/home-health-hospice) — Care Compare star
  ratings, ownership, OASIS / claims quality vs national benchmarks
  for home-health agencies, and CAHPS family-caregiver survey plus
  Hospice Item Set process measures for hospices.
- [Clinicians and industry payments](/clinicians) — Open Payments'
  2024 general-payment file joined to the clinician roster,
  Part B utilization, and Part D prescribing: dollar
  concentration, top payers and specialties, and observational
  associations between industry payments and prescribing volume.
- [Marketplace (QHPs)](/marketplace) — PY2026 Federally-Facilitated
  Marketplace qualified health plans: benchmark silver premiums by
  state and county, premium spread by metal level, issuer
  concentration, the CSR deductible cliff, and stand-alone dental.

## Warehouse coverage

```sql mart_coverage
select
    'fct_part_d_drug_spending' as mart,
    count(*) as row_count,
    cast(min(spending_year) as varchar)
        || '–' || cast(max(spending_year) as varchar) as coverage
from cms.part_d_drug_spending
union all
select
    'fct_part_b_drug_spending',
    count(*),
    cast(min(spending_year) as varchar)
        || '–' || cast(max(spending_year) as varchar)
from cms.part_b_drug_spending
union all
select
    'fct_hospital_quality',
    count(*),
    cast(count(distinct measure_id) as varchar) || ' measures'
from cms.hospital_quality
union all
select
    'fct_hospital_readmissions',
    rows_total,
    cast(conditions as varchar) || ' conditions'
from cms.hospital_readmissions_overview
union all
select
    'fct_hospital_vbp',
    hospitals,
    'FY' || cast(fiscal_year as varchar)
from cms.hospital_vbp_overview
union all
select
    'fct_hospital_utilization',
    count(*),
    'snapshot as of ' || cast(max(as_of) as varchar)
from cms.hospital_utilization
union all
select
    'fct_prescriber_drug_spending',
    total_rows,
    'snapshot as of ' || cast(as_of as varchar)
from cms.prescriber_stats
union all
select
    'dim_nursing_home',
    facilities,
    cast(states as varchar) || ' states'
from cms.nursing_home_stats
union all
select
    'fct_nursing_home_quality',
    quality_rows,
    cast(quality_measures as varchar) || ' measures'
from cms.nursing_home_stats
union all
select
    'fct_nursing_home_enforcement',
    enforcement_rows,
    'snapshot as of ' || cast(enforcement_as_of as varchar)
from cms.nursing_home_stats
union all
select
    'dim_home_health_agency',
    agencies,
    cast(states as varchar) || ' states'
from cms.home_health_stats
union all
select
    'fct_home_health_quality',
    quality_rows,
    cast(quality_measures as varchar) || ' measures'
from cms.home_health_stats
union all
select
    'dim_hospice',
    hospices,
    cast(states as varchar) || ' states'
from cms.hospice_stats
union all
select
    'fct_hospice_quality',
    quality_rows,
    cast(his_hci_measures as varchar) || ' measures'
from cms.hospice_stats
union all
select
    'fct_hospice_cahps',
    cahps_rows,
    cast(cahps_measures as varchar) || ' CAHPS measures'
from cms.hospice_stats
union all
select
    'dim_hospital',
    count(*),
    cast(count(distinct state) as varchar) || ' states'
from cms.dim_hospital
union all
select
    'dim_drug',
    count(*),
    cast(count(case when in_part_b and in_part_d then 1 end) as varchar)
        || ' in both programs'
from cms.dim_drug
union all
select
    'fct_industry_payments',
    records,
    cast(payment_year as varchar) || ' program year'
from cms.clinician_payment_stats
union all
select
    'dim_qhp_plan',
    plans,
    cast(plan_year as varchar) || ' plan year'
from cms.qhp_stats
union all
select
    'fct_qhp_premiums',
    premium_rows,
    cast(states as varchar) || ' FFM states'
from cms.qhp_stats
union all
select
    'fct_qhp_cost_sharing',
    cost_sharing_rows,
    cast(counties as varchar) || ' counties'
from cms.qhp_stats
order by mart
```

```sql headline
select
    (select count(*) from cms.dim_hospital) as hospitals,
    (select count(*) from cms.dim_drug) as drugs,
    (select max(spending_year) from cms.part_d_drug_spending) as latest_spending_year
```

<BigValue data={headline} value=hospitals title="Hospitals" fmt=num0 />
<BigValue data={headline} value=drugs title="Drugs" fmt=num0 />
<BigValue data={headline} value=latest_spending_year title="Latest spending year" fmt=id />

<DataTable data={mart_coverage}>
  <Column id=mart title="Mart" />
  <Column id=row_count title="Rows" fmt=num0 />
  <Column id=coverage title="Coverage" />
</DataTable>

The warehouse is rebuilt locally by the Dagster `full_refresh_job`
(raw CMS extracts → dbt staging → the marts above); these pages query
the marts only.
