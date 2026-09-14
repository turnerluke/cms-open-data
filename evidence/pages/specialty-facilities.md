---
title: Specialty facilities
---

Medicare-certified specialty facilities from CMS Care Compare: outpatient
dialysis clinics from `dim_dialysis_facility` and `fct_dialysis_quality`,
inpatient rehabilitation facilities from `dim_irf`, and long-term care
hospitals from `dim_ltch`. All three populations sit outside the acute-
care `dim_hospital` universe — see the caveats for the CCN-namespace
details. Every view below reads a pre-aggregated source query; the raw
facility and measure grains never leave the warehouse.

```sql headline
select
    dialysis_facilities,
    dialysis_states,
    dialysis_for_profit,
    dialysis_chain_owned,
    dialysis_stations,
    dialysis_rated,
    dialysis_avg_stars,
    dialysis_as_of,
    irf_facilities,
    irf_states,
    irf_freestanding,
    irf_hospital_units,
    irf_as_of,
    ltch_facilities,
    ltch_states,
    ltch_with_bed_count,
    ltch_total_beds,
    ltch_avg_beds,
    ltch_as_of,
    dialysis_quality_rows,
    dialysis_quality_measures,
    dialysis_quality_as_of
from cms.specialty_facility_stats
```

<BigValue data={headline} value=dialysis_facilities title="Dialysis facilities" fmt=num0 />
<BigValue data={headline} value=irf_facilities title="Inpatient rehab facilities" fmt=num0 />
<BigValue data={headline} value=ltch_facilities title="Long-term care hospitals" fmt=num0 />
<BigValue data={headline} value=dialysis_avg_stars title="Avg dialysis five-star" fmt=num2 />

# Dialysis facilities

## Reach and services

<Value data={headline} column=dialysis_facilities fmt=num0 /> Medicare-
certified outpatient dialysis facilities operate across
<Value data={headline} column=dialysis_states fmt=num0 /> states and
territories, running roughly
<Value data={headline} column=dialysis_stations fmt=num0 /> dialysis
stations combined. In-center hemodialysis is nearly universal;
peritoneal dialysis is offered by a bit over half of clinics, home
hemodialysis training by roughly a third, and a late shift by fewer
than one in six.

```sql dialysis_services
select service, facilities from cms.dialysis_service_offerings
```

<BarChart
  data={dialysis_services}
  x=service
  y=facilities
  swapXY=true
  title="Dialysis facilities by service offered"
  yFmt=num0
/>

## The chain landscape

Two operators — DaVita and Fresenius Medical Care — run roughly
three-quarters of every Medicare-certified dialysis facility in the
country between them. Independent clinics (no chain affiliation) are
the third-largest cohort, and everything else is a long tail. Both
DaVita's and Fresenius's chain-averaged five-star rating sits within
a tenth of a point of the national dialysis mean; the Kaiser
Permanente-run clinics are a small (22-facility) outlier, averaging
nearly a full star higher.

```sql dialysis_chains
select chain, facilities, stations, rated_facilities, avg_stars
from cms.dialysis_chain_summary
order by facilities desc
limit 10
```

<BarChart
  data={dialysis_chains}
  x=chain
  y=facilities
  swapXY=true
  title="Top dialysis chains (and independents) by facility count"
  yFmt=num0
/>

<DataTable data={dialysis_chains} rows=10>
  <Column id=chain title="Chain" wrap=true />
  <Column id=facilities title="Facilities" fmt=num0 />
  <Column id=stations title="Stations" fmt=num0 />
  <Column id=rated_facilities title="Rated" fmt=num0 />
  <Column id=avg_stars title="Avg stars" fmt=num2 />
</DataTable>

## Five-star ratings

CMS assigns each dialysis facility a 1–5 star rating in whole-star
increments based on a composite of clinical measures. The overall
distribution centers on three stars, with about
<Value data={headline} column=dialysis_facilities fmt=num0 /> minus
<Value data={headline} column=dialysis_rated fmt=num0 /> facilities
unrated in the current vintage (typically new or low-volume clinics).

```sql dialysis_stars
select star_rating, facilities
from cms.dialysis_star_distribution
order by sort_order
```

<BarChart
  data={dialysis_stars}
  x=star_rating
  y=facilities
  title="Dialysis facilities by five-star rating"
  yFmt=num0
/>

## Top states

```sql dialysis_states_top
select state, facilities, stations, for_profit_share, chain_share, avg_stars
from cms.dialysis_state_summary
order by facilities desc
limit 15
```

<DataTable data={dialysis_states_top} rows=15>
  <Column id=state title="State" />
  <Column id=facilities title="Facilities" fmt=num0 />
  <Column id=stations title="Stations" fmt=num0 />
  <Column id=for_profit_share title="For-profit" fmt=pct0 />
  <Column id=chain_share title="Chain-owned" fmt=pct0 />
  <Column id=avg_stars title="Avg stars" fmt=num2 />
</DataTable>

## Standardized-ratio measures

The five standardized-ratio measures in `fct_dialysis_quality` compare
each clinic's observed outcome (mortality, hospitalization, infection,
readmission, ED visits) against a case-mix-adjusted expected value.
CMS bins each facility's ratio into "Better than Expected", "As
Expected", or "Worse than Expected" using confidence-interval overlap
with 1.0; facilities without enough denominator to compute a ratio
appear as "Not Available". The infection ratio (SIR) stands out for
its lopsided tail: about 2,800 facilities land "Better than Expected"
against only 47 "Worse"; the other four ratios sit "as expected" for
the large majority of reporting facilities.

```sql dialysis_ratios
select measure_code, measure_name, category, facilities
from cms.dialysis_quality_ratios
order by measure_code, category_sort
```

<BarChart
  data={dialysis_ratios}
  x=measure_code
  y=facilities
  series=category
  type=stacked100
  title="Standardized-ratio measures: facility categorization"
  yFmt=pct0
/>

<DataTable data={dialysis_ratios} rows=20 groupBy=measure_name groupType=section>
  <Column id=category title="Category" />
  <Column id=facilities title="Facilities" fmt=num0 />
</DataTable>

## Selected percent-of-patient measures

Percent-family dialysis measures publish an unweighted average across
reporting facilities. Adherence measures (adequacy of dialysis — the
Kt/V targets) run above 90%, long-term-catheter use averages about
19%, and the two anemia measures are asymmetric (hemoglobin under 10
is common, over 12 is rare). Healthcare-worker COVID-19 vaccination
adherence stands out as very low in this vintage — mean about 4% at
the roughly 3,900 reporting facilities.

```sql dialysis_percent_measures
select
    measure_code,
    measure_name,
    denominator_unit,
    facilities_reporting,
    facilities_in_scope,
    avg_score
from cms.dialysis_quality_percent_measures
order by avg_score desc nulls last
```

<DataTable data={dialysis_percent_measures} rows=10>
  <Column id=measure_code title="Code" />
  <Column id=measure_name title="Measure" wrap=true />
  <Column id=denominator_unit title="Unit" />
  <Column id=facilities_reporting title="Reporting" fmt=num0 />
  <Column id=facilities_in_scope title="In scope" fmt=num0 />
  <Column id=avg_score title="Avg %" fmt=num2 />
</DataTable>

# Inpatient rehabilitation facilities

## Freestanding vs hospital unit

<Value data={headline} column=irf_facilities fmt=num0 /> Medicare-
certified IRFs operate across
<Value data={headline} column=irf_states fmt=num0 /> states and
territories. IRFs split into two structurally different populations
that both bill under IRF PPS: freestanding rehabilitation hospitals
(their own CCN and physical plant) and hospital-based rehab units
carved out of an acute-care hospital. Roughly two-thirds are hospital
units; freestandings are more concentrated in the largest states —
Texas alone has 77 of the 410 freestanding IRFs nationally.

```sql irf_ownership
select ownership_type, facilities, freestanding, hospital_units
from cms.irf_ownership_summary
order by facilities desc
```

<BarChart
  data={irf_ownership}
  x=ownership_type
  y=facilities
  swapXY=true
  title="IRFs by ownership type"
  yFmt=num0
/>

<DataTable data={irf_ownership} rows=10>
  <Column id=ownership_type title="Ownership" />
  <Column id=facilities title="Facilities" fmt=num0 />
  <Column id=freestanding title="Freestanding" fmt=num0 />
  <Column id=hospital_units title="Hospital unit" fmt=num0 />
</DataTable>

## Top states

```sql irf_states_top
select state, facilities, freestanding, hospital_units
from cms.irf_state_summary
order by facilities desc
limit 15
```

<BarChart
  data={irf_states_top}
  x=state
  y={['freestanding', 'hospital_units']}
  type=stacked
  title="Top states by IRF count (freestanding + hospital unit)"
  yFmt=num0
/>

# Long-term care hospitals

## Population and ownership

<Value data={headline} column=ltch_facilities fmt=num0 /> LTCHs operate
across <Value data={headline} column=ltch_states fmt=num0 /> states.
Unlike the near-parity ownership mix among IRFs, LTCHs are dominated
by for-profit operators (about 70% of the population), with non-profit
the runner-up. Bed capacity is populated for
<Value data={headline} column=ltch_with_bed_count fmt=num0 /> of
<Value data={headline} column=ltch_facilities fmt=num0 /> LTCHs and
totals <Value data={headline} column=ltch_total_beds fmt=num0 />
certified beds nationwide.

```sql ltch_ownership
select ownership_type, facilities, facilities_with_beds, total_beds, avg_beds
from cms.ltch_ownership_summary
order by facilities desc
```

<BarChart
  data={ltch_ownership}
  x=ownership_type
  y=facilities
  swapXY=true
  title="LTCHs by ownership type"
  yFmt=num0
/>

## Bed capacity

Most LTCHs are small — half sit under 50 beds — but a long tail of
larger facilities (100+ beds) drives most of the aggregate capacity.
The single largest LTCH in the file reports 760 beds.

```sql ltch_beds
select bed_bucket, facilities
from cms.ltch_bed_distribution
order by sort_order
```

<BarChart
  data={ltch_beds}
  x=bed_bucket
  y=facilities
  title="LTCHs by bed-count bucket"
  yFmt=num0
/>

## Top states

```sql ltch_states_top
select state, facilities, total_beds
from cms.ltch_state_summary
order by facilities desc
limit 15
```

<DataTable data={ltch_states_top} rows=15>
  <Column id=state title="State" />
  <Column id=facilities title="Facilities" fmt=num0 />
  <Column id=total_beds title="Beds" fmt=num0 />
</DataTable>

## Caveats

- **Snapshot vintage.** Dialysis directory and quality data come from
  the Care Compare snapshot as of
  <Value data={headline} column=dialysis_as_of fmt=longdate />, IRFs
  as of
  <Value data={headline} column=irf_as_of fmt=longdate />, and LTCHs
  as of
  <Value data={headline} column=ltch_as_of fmt=longdate />. Every
  figure above is a point-in-time snapshot — the marts don't carry
  facility-level history.
- **Dialysis measure suppression.** `fct_dialysis_quality` publishes
  <Value data={headline} column=dialysis_quality_rows fmt=num0 />
  rows at the (ccn, measure_code) grain across
  <Value data={headline} column=dialysis_quality_measures fmt=num0 />
  measures, but not every facility reports every measure. CMS carries
  an availability code on each row; `is_reported` is true when the
  score is present (`availability_code = '001'`) and non-reported
  rows have `NULL` in `score_numeric` (for the ratio measures, CMS
  labels them with the literal category `Not Available`, not
  `NULL`). Every reporting count above filters to
  `is_reported = true`; percent-family averages exclude suppressed
  rows, and the ratio "Not Available" bucket is the suppressed count
  itself.
- **CCN namespaces.** These three specialty populations are almost
  entirely disjoint from the acute-care hospital universe. Zero of
  the <Value data={headline} column=dialysis_facilities fmt=num0 />
  dialysis facilities share a CCN with `dim_hospital`; only 5 LTCH
  CCNs overlap (dual certifications). All 410 freestanding IRFs sit
  outside `dim_hospital`; 762 of the 812 hospital-unit IRFs can be
  traced back to a parent acute-care hospital via the CCN
  position-3 → `'0'` rewrite the source file uses, but the remaining
  50 units don't reconcile. Cross-mart joins should treat specialty
  CCNs as their own space.
- **County coverage is FFM-scoped.** `dim_county` is the Federally-
  Facilitated Marketplace's rating-area geography (30 FFM states),
  so specialty-facility rows for the 20 non-FFM states carry a
  county name but no `dim_county` match. Only about half of dialysis
  clinics, ~62% of IRFs, and ~64% of LTCHs land in an FFM county.
- **State code counts include territories.** The
  <Value data={headline} column=dialysis_states fmt=num0 />-state
  dialysis footprint,
  <Value data={headline} column=irf_states fmt=num0 />-state IRF
  footprint, and
  <Value data={headline} column=ltch_states fmt=num0 />-state LTCH
  footprint count U.S. territories (Puerto Rico, Guam, USVI, etc.)
  and DC alongside the 50 states, matching the raw CMS files.
- **Unweighted averages.** Every star / score / bed average above
  weights each facility equally, regardless of station count, bed
  count, or patient volume.
