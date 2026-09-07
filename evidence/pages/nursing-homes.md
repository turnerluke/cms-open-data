---
title: Nursing homes
---

Medicare- and Medicaid-certified nursing homes from CMS Care Compare:
facility profile and star ratings from `dim_nursing_home`, MDS- and
claims-based quality measures from `fct_nursing_home_quality`, and
health-inspection deficiencies and penalties from
`fct_nursing_home_enforcement`. Every view below reads a
pre-aggregated source query — the raw grains (14.7k homes, 308k
measure rows, 435k enforcement rows) never leave the warehouse.

```sql headline
select
    facilities,
    rated_facilities,
    median_overall_rating,
    avg_overall_rating,
    sff_facilities,
    sff_candidate_facilities,
    abuse_icon_facilities,
    certified_beds,
    total_fine_amount,
    fines,
    payment_denials,
    deficiency_citations,
    earliest_penalty_date,
    provider_as_of
from cms.nursing_home_stats
```

<BigValue data={headline} value=facilities title="Nursing homes" fmt=num0 />
<BigValue data={headline} value=median_overall_rating title="Median overall stars" fmt=num0 />
<BigValue data={headline} value=total_fine_amount title="Fines on the books" fmt=usd1m />
<BigValue data={headline} value=sff_facilities title="Special focus facilities" fmt=num0 />

## Star ratings

Each home carries four 1–5 star ratings: the overall rating plus its
three components (health inspections, quality measures, staffing).
The overall distribution centers on
<Value data={headline} column=median_overall_rating fmt=num0 /> stars,
but the components pull in different directions — health-inspection
stars skew low while quality-measure stars skew high.

```sql star_distribution
select
    rating_type,
    stars,
    facilities
from cms.nursing_home_rating_distribution
order by sort_order, stars
```

<BarChart
  data={star_distribution}
  x=stars
  y=facilities
  series=rating_type
  type=grouped
  title="Facilities by star rating (overall and components)"
/>

<Value data={headline} column=facilities fmt=num0 /> homes are in the
dimension;
<Value data={headline} column=rated_facilities fmt=num0 /> carry an
overall rating (new or recently recertified homes are unrated).

## Ownership

For-profit homes — the large majority — average materially lower
overall ratings than non-profit and government homes, with lower
nurse staffing hours and higher staff turnover.

```sql ownership
select
    ownership_type,
    facilities,
    avg_overall_rating,
    avg_nurse_staffing_hours,
    avg_nursing_staff_turnover,
    special_focus_facilities
from cms.nursing_home_ownership_summary
order by avg_overall_rating desc
```

<BarChart
  data={ownership}
  x=ownership_type
  y=avg_overall_rating
  swapXY=true
  title="Average overall star rating by ownership type"
  yFmt=num2
/>

<DataTable data={ownership} rows=13>
  <Column id=ownership_type title="Ownership" wrap=true />
  <Column id=facilities title="Facilities" fmt=num0 />
  <Column id=avg_overall_rating title="Avg stars" fmt=num2 />
  <Column id=avg_nurse_staffing_hours title="Nurse hrs/resident-day" fmt=num2 />
  <Column id=avg_nursing_staff_turnover title="Staff turnover" fmt=pct0 />
  <Column id=special_focus_facilities title="SFF + candidates" fmt=num0 />
</DataTable>

## States

```sql state_summary
select
    state,
    facilities,
    avg_overall_rating,
    for_profit_share,
    special_focus_facilities,
    total_fine_amount,
    fine_amount_per_facility
from cms.nursing_home_state_summary
order by facilities desc
```

```sql top_fine_states
select
    state,
    total_fine_amount
from cms.nursing_home_state_summary
order by total_fine_amount desc
limit 10
```

<BarChart
  data={top_fine_states}
  x=state
  y=total_fine_amount
  title="Top 10 states by total fines on the books"
  yFmt=usd1m
/>

Average ratings vary widely by state, and the gap tracks the
for-profit share — the biggest for-profit-heavy systems (Texas,
Illinois) sit at the bottom of the ratings table while averaging some
of the largest fine totals.

<DataTable data={state_summary} rows=15>
  <Column id=state title="State" />
  <Column id=facilities title="Facilities" fmt=num0 />
  <Column id=avg_overall_rating title="Avg stars" fmt=num2 />
  <Column id=for_profit_share title="For-profit share" fmt=pct0 />
  <Column id=special_focus_facilities title="SFF + candidates" fmt=num0 />
  <Column id=total_fine_amount title="Total fines" fmt=usd0 />
  <Column id=fine_amount_per_facility title="Fines / facility" fmt=usd0 />
</DataTable>

## Quality measures

National averages for the resident-assessment (MDS) and Medicare-claims
measures. Scores are only comparable **within** a measure: MDS scores
are percentages of residents, while the two claims long-stay measures
are rates per 1,000 resident-days — so the table never aggregates
across measures, and the chart below is limited to the MDS
percentage measures used in the five-star quality rating.

```sql five_star_mds
select
    measure_code,
    measure_name,
    resident_type,
    facilities_reporting,
    avg_score
from cms.nursing_home_quality_measures
where used_in_five_star_rating and measure_source = 'mds'
order by avg_score desc
```

<BarChart
  data={five_star_mds}
  x=measure_name
  y=avg_score
  series=resident_type
  swapXY=true
  title="Average score, MDS five-star measures (% of residents)"
  yFmt=num1
/>

```sql all_measures
select
    measure_source,
    measure_code,
    measure_name,
    resident_type,
    used_in_five_star_rating,
    facilities_reporting,
    avg_score,
    median_score
from cms.nursing_home_quality_measures
order by measure_source, resident_type, measure_code
```

<DataTable data={all_measures} rows=25>
  <Column id=measure_source title="Source" />
  <Column id=measure_code title="Code" />
  <Column id=measure_name title="Measure" wrap=true />
  <Column id=resident_type title="Residents" />
  <Column id=used_in_five_star_rating title="In five-star" />
  <Column id=facilities_reporting title="Reporting" fmt=num0 />
  <Column id=avg_score title="Avg" fmt=num1 />
  <Column id=median_score title="Median" fmt=num1 />
</DataTable>

## Enforcement

Health-inspection deficiency citations and the penalties that follow
them. The two histories have different windows: the deficiency file
covers roughly the last three survey cycles (counts thin out before
2022), while penalties reach back only to
<Value data={headline} column=earliest_penalty_date fmt=longdate />.
The latest year is partial in both.

```sql enforcement_by_year
select
    action_year,
    deficiency_citations,
    fines,
    total_fine_amount,
    payment_denials
from cms.nursing_home_enforcement_by_year
order by action_year
```

<BarChart
  data={enforcement_by_year}
  x=action_year
  y=deficiency_citations
  title="Deficiency citations by survey year"
  xFmt=id
/>

<BarChart
  data={enforcement_by_year}
  x=action_year
  y=total_fine_amount
  title="Fines imposed by year"
  xFmt=id
  yFmt=usd1m
/>

### Most-cited deficiencies

```sql deficiency_tags
select
    deficiency_tag,
    deficiency_description,
    citations,
    facilities_cited,
    complaint_share
from cms.nursing_home_deficiency_tags
order by citations desc
limit 10
```

<DataTable data={deficiency_tags} rows=10>
  <Column id=deficiency_tag title="Tag" />
  <Column id=deficiency_description title="Deficiency" wrap=true />
  <Column id=citations title="Citations" fmt=num0 />
  <Column id=facilities_cited title="Facilities cited" fmt=num0 />
  <Column id=complaint_share title="From complaints" fmt=pct0 />
</DataTable>

Infection prevention and control tops the list — cited at
four out of five homes at least once in the current survey window.

## Caveats

- **Snapshot vintage.** All three marts come from the same Care
  Compare release, `as_of`
  <Value data={headline} column=provider_as_of fmt=longdate />. There
  is no facility-level history — every figure above is a
  point-in-time snapshot except the enforcement dates.
- **Unrated homes.** The
  <Value data={headline} column=facilities fmt=num0 /> −
  <Value data={headline} column=rated_facilities fmt=num0 /> homes
  without an overall rating drop out of every rating average above
  (but still count in facility totals).
- **Special focus.** The headline counts CMS's Special Focus
  Facility program participants
  (<Value data={headline} column=sff_facilities fmt=num0 />); another
  <Value data={headline} column=sff_candidate_facilities fmt=num0 />
  homes are SFF candidates, and
  <Value data={headline} column=abuse_icon_facilities fmt=num0 />
  carry the abuse icon. The "SFF + candidates" columns in the
  ownership and state tables count participants *and* candidates
  together, so they sum to more than the headline figure.
- **Enforcement windows differ.** Fine totals cover only penalties
  since
  <Value data={headline} column=earliest_penalty_date fmt=longdate />
  and reflect fines *imposed*, not necessarily collected; deficiency
  counts cover a longer (but still truncated) survey history. Neither
  is a complete history, so year-over-year changes partly reflect the
  window edges.
- **Suppressed scores.** Quality-measure scores CMS suppresses are
  `NULL` and excluded from averages; `facilities_reporting` counts
  only non-null scores.
- **Unweighted averages.** All rating and score averages weight each
  facility equally, regardless of bed count or resident volume.
