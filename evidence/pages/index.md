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
- [Hospital quality](/hospital-quality) — overall star ratings and
  healthcare-associated infection performance.
- [Cost vs quality](/cost-vs-quality) — Medicare inpatient payment per
  discharge by star rating, with case mix as the confounder.
- [Prescribers](/prescribers) — who drives spending on the top Part D
  drugs: specialties, top-1% concentration, and billed-vs-gross cost.

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
