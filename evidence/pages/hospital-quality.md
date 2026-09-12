---
title: Hospital quality
---

Quality of Medicare-certified hospitals from CMS Care Compare: the
overall star rating from `dim_hospital`, and healthcare-associated
infection (HAI) results from `fct_hospital_quality`. Quality scores are
only comparable **within** a measure, so each view below is filtered to
specific `measure_id`s and never aggregates across measures.

## Overall star ratings

```sql rating_coverage
select
    count(*) as total_hospitals,
    count(hospital_overall_rating) as rated_hospitals,
    count(hospital_overall_rating) / cast(count(*) as double) as rated_share,
    avg(hospital_overall_rating) as avg_rating
from cms.dim_hospital
```

<BigValue data={rating_coverage} value=total_hospitals title="Hospitals" fmt=num0 />
<BigValue data={rating_coverage} value=rated_share title="With a star rating" fmt=pct1 />
<BigValue data={rating_coverage} value=avg_rating title="Average stars" fmt=num2 />

```sql star_distribution
select
    hospital_overall_rating as stars,
    count(*) as hospitals
from cms.dim_hospital
where hospital_overall_rating is not null
group by 1
order by 1
```

<BarChart
  data={star_distribution}
  x=stars
  y=hospitals
  title="Hospitals by overall star rating"
/>

## Healthcare-associated infections

Standardized infection ratios (SIR): below 1.0 means fewer infections
than the national baseline predicts, above 1.0 means more. Each SIR
measure is summarized separately. Averages are unweighted means across
reporting hospitals — small and large facilities count equally.

```sql infection_sir
select
    measure_id,
    any_value(measure_name) as measure_name,
    count(score) as hospitals_reporting,
    avg(score) as avg_sir,
    count(case when compared_to_national ilike 'better%' then 1 end)
        as better_than_national,
    count(case when compared_to_national ilike 'worse%' then 1 end)
        as worse_than_national
from cms.hospital_quality
where
    measure_domain = 'infections'
    and measure_id in (
        'HAI_1_SIR', 'HAI_2_SIR', 'HAI_3_SIR',
        'HAI_4_SIR', 'HAI_5_SIR', 'HAI_6_SIR'
    )
group by 1
order by 1
```

<BarChart
  data={infection_sir}
  x=measure_id
  y=avg_sir
  swapXY=true
  title="Average (unweighted) SIR by infection measure (1.0 = national baseline)"
  yFmt=num2
>
  <ReferenceLine y=1 label="National baseline" />
</BarChart>

<DataTable data={infection_sir}>
  <Column id=measure_id title="Measure" />
  <Column id=measure_name title="Description" wrap=true />
  <Column id=hospitals_reporting title="Reporting" fmt=num0 />
  <Column id=avg_sir title="Avg SIR" fmt=num2 />
  <Column id=better_than_national title="Better than national" fmt=num0 />
  <Column id=worse_than_national title="Worse than national" fmt=num0 />
</DataTable>

## Hospital Readmissions Reduction Program (`HRRP`)

CMS's Hospital Readmissions Reduction Program docks Medicare inpatient
payments for hospitals whose 30-day risk-adjusted readmissions exceed
the national expected rate for six clinical conditions: acute
myocardial infarction (`AMI`), coronary artery bypass grafting
(`CABG`), chronic obstructive pulmonary disease (`COPD`), heart
failure (`HF`), elective primary hip or knee replacement (`HIP-KNEE`),
and pneumonia (`PN`). The core signal is the **excess readmission
ratio** — a hospital-condition-level ratio of predicted to expected
readmissions where `ERR > 1` triggers a penalty.

```sql hrrp_overview
select
    rows_total,
    hospitals,
    conditions,
    measured_rows,
    penalized_rows,
    penalized_share
from cms.hospital_readmissions_overview
```

<BigValue data={hrrp_overview} value=hospitals title="Hospitals in HRRP" fmt=num0 />
<BigValue data={hrrp_overview} value=measured_rows title="Hospital-condition rows with ERR" fmt=num0 />
<BigValue data={hrrp_overview} value=penalized_share title="Share of measured rows penalized" fmt=pct1 />

Every hospital appears in all six conditions (18,330 rows = 3,055
hospitals × 6 conditions), but CMS suppresses low-volume cells, so
only 11,720 of the 18,330 rows carry an ERR. Roughly half of those
measured rows (48%) sit above 1.0 — that's expected by construction,
since `ERR` is calibrated so the national aggregate lands at 1.0.

### `ERR` distribution by condition

```sql hrrp_by_condition
select
    condition,
    hospitals_measured,
    avg_err,
    median_err,
    min_err,
    max_err,
    penalized_hospitals,
    penalized_share
from cms.hospital_readmissions_by_condition
order by condition
```

```sql hrrp_err_distribution
select
    condition,
    err_bin,
    hospitals
from cms.hospital_readmissions_err_distribution
order by condition, err_bin
```

<BarChart
  data={hrrp_err_distribution}
  x=err_bin
  y=hospitals
  series=condition
  type=grouped
  title="ERR distribution by condition (bin width 0.02)"
  xAxisTitle="Excess readmission ratio"
  xFmt=num2
/>

<DataTable data={hrrp_by_condition}>
  <Column id=condition title="Condition" />
  <Column id=hospitals_measured title="Hospitals measured" fmt=num0 />
  <Column id=median_err title="Median ERR" fmt=num3 />
  <Column id=avg_err title="Avg ERR" fmt=num3 />
  <Column id=min_err title="Min ERR" fmt=num2 />
  <Column id=max_err title="Max ERR" fmt=num2 />
  <Column id=penalized_hospitals title="Penalized" fmt=num0 />
  <Column id=penalized_share title="Penalized share" fmt=pct1 />
</DataTable>

Reporting depth varies by condition: pneumonia (2,715 hospitals) and
heart failure (2,621) are close to universal, while coronary artery
bypass (878) is limited to hospitals that perform enough cases.
Penalized shares hover near 46–50% for every condition — the tails
are what differ.

### `HRRP` by state

Joining to `dim_hospital` for the state attaches state labels; ~20
CCNs in the HRRP file don't reconcile with the Care Compare hospital
roster and are dropped by the inner join.

```sql hrrp_state
select
    state,
    hospitals,
    measured_rows,
    avg_err,
    penalized_rows,
    penalized_share
from cms.hospital_readmissions_state
order by hospitals desc
```

<DataTable data={hrrp_state} rows=15>
  <Column id=state title="State" />
  <Column id=hospitals title="Hospitals" fmt=num0 />
  <Column id=measured_rows title="Measured rows" fmt=num0 />
  <Column id=avg_err title="Avg ERR" fmt=num3 />
  <Column id=penalized_rows title="Penalized" fmt=num0 />
  <Column id=penalized_share title="Penalized share" fmt=pct1 />
</DataTable>

## Hospital Value-Based Purchasing (`VBP`)

The Value-Based Purchasing program redistributes 2% of Medicare
inpatient payments based on a **total performance score** built from
four equally-weighted domains: clinical outcomes, person and community
engagement, safety, and efficiency and cost reduction. The domain
scores below are the *weighted* contribution to the 100-point total
(each domain nominally worth 25 points before reweighting).

```sql vbp_overview
select
    hospitals,
    fiscal_year,
    avg_tps,
    median_tps,
    min_tps,
    max_tps,
    reweighted_hospitals
from cms.hospital_vbp_overview
```

<BigValue data={vbp_overview} value=hospitals title="Hospitals in VBP" fmt=num0 />
<BigValue data={vbp_overview} value=fiscal_year title="Fiscal year" fmt=id />
<BigValue data={vbp_overview} value=avg_tps title="Avg TPS" fmt=num2 />
<BigValue data={vbp_overview} value=median_tps title="Median TPS" fmt=num2 />

FY2026 covers 2,455 hospitals; Maryland participates under an
all-payer waiver and does not appear in the file. 156 hospitals were
reweighted on at least one domain — CMS drops a domain when it can't
score enough measures — so the domain averages below exclude those
NULLs.

### Total performance score distribution

```sql vbp_tps_distribution
select
    tps_bin,
    hospitals
from cms.hospital_vbp_tps_distribution
order by tps_bin
```

<BarChart
  data={vbp_tps_distribution}
  x=tps_bin
  y=hospitals
  title="Hospitals by total performance score (bin width 5)"
  xAxisTitle="Total performance score"
/>

TPS is right-skewed: the median hospital lands at 29.5 out of 100, but
a long tail runs into the 70s and higher — those hospitals capture the
positive side of the 2% redistribution.

### Domain decomposition

```sql vbp_domains
select
    domain,
    avg_weighted_score,
    scored_hospitals,
    reweighted_hospitals
from cms.hospital_vbp_domains
order by avg_weighted_score desc
```

<BarChart
  data={vbp_domains}
  x=domain
  y=avg_weighted_score
  swapXY=true
  title="Average weighted domain contribution to TPS"
  yFmt=num2
/>

<DataTable data={vbp_domains}>
  <Column id=domain title="Domain" />
  <Column id=avg_weighted_score title="Avg weighted score" fmt=num3 />
  <Column id=scored_hospitals title="Scored" fmt=num0 />
  <Column id=reweighted_hospitals title="Reweighted (NULL)" fmt=num0 />
</DataTable>

Safety and person-and-community-engagement contribute the most on
average; clinical outcomes and efficiency contribute the least. The
domains are equally weighted before reweighting, so these gaps reflect
how hard each domain is to score highly on rather than a policy
preference.

### `TPS` vs overall star rating

Both signals summarize hospital performance but from very different
inputs: the overall star rating rolls up dozens of Care Compare
measures into a 1–5 rating, while TPS blends the four VBP domains.
Plotting average TPS by star bucket confirms they move together —
five-star hospitals average roughly twice the TPS of one-star
hospitals. The chart covers 2,417 of the 2,455 VBP hospitals: 9
CCNs don't reconcile with `dim_hospital` (the same vintage gap as
the HRRP state view) and another 29 hospitals have no published
star rating.

```sql vbp_by_star
select
    stars,
    hospitals,
    avg_tps,
    median_tps
from cms.hospital_vbp_by_star
order by stars
```

<BarChart
  data={vbp_by_star}
  x=stars
  y=avg_tps
  title="Average TPS by overall Care Compare star rating"
  yFmt=num2
/>

<DataTable data={vbp_by_star}>
  <Column id=stars title="Overall stars" />
  <Column id=hospitals title="Hospitals" fmt=num0 />
  <Column id=avg_tps title="Avg TPS" fmt=num2 />
  <Column id=median_tps title="Median TPS" fmt=num2 />
</DataTable>
