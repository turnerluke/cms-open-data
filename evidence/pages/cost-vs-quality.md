---
title: Cost vs quality
---

Do higher-rated hospitals cost Medicare more or less? This page joins
`fct_hospital_utilization` (one row per hospital `ccn`, Medicare
fee-for-service inpatient payments) to the Care Compare overall star
rating in `dim_hospital`. All dollar comparisons use **payment per
discharge**, never raw totals, so hospital volume doesn't confound the
star groups.

```sql coverage
select
    count(*) as utilization_hospitals,
    count(d.ccn) as matched_hospitals,
    count(*) - count(d.ccn) as unmatched_hospitals,
    count(d.hospital_overall_rating) as rated_hospitals,
    count(d.ccn) - count(d.hospital_overall_rating) as unrated_matched_hospitals,
    sum(
        case
            when d.hospital_overall_rating is not null
                then u.inpatient_total_medicare_payment_amount
        end
    ) as rated_inpatient_medicare_payments
from cms.hospital_utilization as u
left join cms.dim_hospital as d using (ccn)
```

<BigValue data={coverage} value=rated_hospitals title="Star-rated hospitals with utilization data" fmt=num0 />
<BigValue data={coverage} value=rated_inpatient_medicare_payments title="Inpatient Medicare payments covered" fmt=usd1b />
<BigValue data={coverage} value=unrated_matched_hospitals title="Matched but unrated (excluded below)" fmt=num0 />

## Payment per discharge by star rating

Median Medicare payment per inpatient discharge, by overall star
rating. The raw medians are nearly flat — 1-star hospitals collect
about a thousand dollars *more* per discharge than 4-star hospitals,
with 5-star hospitals ticking back up.

```sql payment_by_stars
select
    d.hospital_overall_rating as stars,
    count(*) as hospitals,
    median(u.inpatient_medicare_payment_per_discharge)
        as median_payment_per_discharge,
    avg(u.inpatient_medicare_payment_per_discharge)
        as mean_payment_per_discharge,
    median(u.inpatient_avg_hcc_risk_score) as median_hcc_risk_score,
    median(
        u.inpatient_medicare_payment_per_discharge
        / u.inpatient_avg_hcc_risk_score
    ) as median_payment_per_discharge_per_risk_unit
from cms.hospital_utilization as u
inner join cms.dim_hospital as d using (ccn)
where d.hospital_overall_rating is not null
group by 1
order by 1
```

<BarChart
  data={payment_by_stars}
  x=stars
  y=median_payment_per_discharge
  title="Median Medicare payment per discharge by star rating"
  yFmt=usd0
/>

But star groups don't treat equally sick patients: the median average
HCC risk score falls from 1-star through 4-star hospitals (ticking up
slightly at 5), so low-star hospitals see sicker-than-expected
inpatients. Crudely scaling each hospital's payment per discharge by
its average HCC risk score flips the endpoints — per unit of expected
patient risk, 5-star hospitals are paid the most and 1-star hospitals
the least.

<BarChart
  data={payment_by_stars}
  x=stars
  y=median_payment_per_discharge_per_risk_unit
  title="Median payment per discharge per unit of HCC risk, by star rating"
  yFmt=usd0
/>

<DataTable data={payment_by_stars}>
  <Column id=stars title="Stars" />
  <Column id=hospitals title="Hospitals" fmt=num0 />
  <Column id=median_payment_per_discharge title="Median $/discharge" fmt=usd0 />
  <Column id=mean_payment_per_discharge title="Mean $/discharge" fmt=usd0 />
  <Column id=median_hcc_risk_score title="Median HCC risk" fmt=num2 />
  <Column id=median_payment_per_discharge_per_risk_unit title="Median $/discharge per risk unit" fmt=usd0 />
</DataTable>

## Case mix, not stars, tracks payment

Each point is one star-rated hospital. Payment per discharge rises
with the hospital's average HCC risk score (correlation ≈ 0.29 among
star-rated hospitals), while its correlation with the star rating
itself is ≈ 0 — case mix, not measured quality, is what tracks
Medicare's per-discharge cost.

```sql payment_vs_risk
select
    d.hospital_overall_rating
    || case when d.hospital_overall_rating = 1 then ' star' else ' stars' end
        as star_group,
    u.inpatient_avg_hcc_risk_score,
    u.inpatient_medicare_payment_per_discharge
from cms.hospital_utilization as u
inner join cms.dim_hospital as d using (ccn)
where
    d.hospital_overall_rating is not null
    and u.inpatient_medicare_payment_per_discharge is not null
```

<ScatterPlot
  data={payment_vs_risk}
  x=inpatient_avg_hcc_risk_score
  y=inpatient_medicare_payment_per_discharge
  series=star_group
  title="Payment per discharge vs average HCC risk score"
  xAxisTitle="Average HCC risk score (inpatient population)"
  yAxisTitle="Medicare payment per discharge"
  yFmt=usd0
  pointSize=4
/>

## Most expensive high-volume hospitals

Star-rated hospitals with at least 1,000 inpatient discharges, ranked
by Medicare payment per discharge. High HCC risk scores in this list
are the case-mix confounder made concrete: these are largely academic
referral centers treating the sickest patients.

```sql expensive_high_volume
select
    d.hospital_name,
    d.state,
    d.hospital_overall_rating as stars,
    u.inpatient_total_discharges,
    u.inpatient_medicare_payment_per_discharge,
    u.inpatient_avg_hcc_risk_score,
    u.inpatient_avg_length_of_stay
from cms.hospital_utilization as u
inner join cms.dim_hospital as d using (ccn)
where
    d.hospital_overall_rating is not null
    and u.inpatient_total_discharges >= 1000
order by u.inpatient_medicare_payment_per_discharge desc
limit 15
```

<DataTable data={expensive_high_volume}>
  <Column id=hospital_name title="Hospital" wrap=true />
  <Column id=state title="State" />
  <Column id=stars title="Stars" />
  <Column id=inpatient_total_discharges title="Discharges" fmt=num0 />
  <Column id=inpatient_medicare_payment_per_discharge title="Medicare $/discharge" fmt=usd0 />
  <Column id=inpatient_avg_hcc_risk_score title="Avg HCC risk" fmt=num2 />
  <Column id=inpatient_avg_length_of_stay title="Avg LOS (days)" fmt=num1 />
</DataTable>

## Caveats

- **Single snapshot, no trend.** The utilization mart is a single
  latest-vintage snapshot with no year column, so nothing here is a
  time series and figures can't be labeled with a year.
- **Inpatient dollars only.** The mart's outpatient dollar columns are
  estimates (per-service average × service count) that **exclude
  outlier payments**, while inpatient totals include them — the two
  aren't comparable, so this page shows inpatient payments only.
- **Join coverage.** <Value data={coverage} column=unmatched_hospitals fmt=num0 />
  of <Value data={coverage} column=utilization_hospitals fmt=num0 />
  utilization CCNs have no `dim_hospital` row and drop out of every
  view above; <Value data={coverage} column=matched_hospitals fmt=num0 />
  hospitals survive the join.
- **Unrated hospitals excluded.** The star-rated views inner-join on a
  non-null rating, excluding
  <Value data={coverage} column=unrated_matched_hospitals fmt=num0 />
  matched-but-unrated hospitals.
- **Stars aren't risk-adjusted here.** The overall rating is a
  hospital-level summary and the payment comparison is unadjusted;
  differences across star groups reflect case mix (HCC risk), teaching
  status, and payment-policy add-ons — not quality alone. The
  per-risk-unit scaling above is a crude ratio, not CMS risk
  adjustment.
