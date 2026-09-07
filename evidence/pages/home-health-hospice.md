---
title: Home health and hospice
---

Medicare-certified home health agencies and hospice providers from
CMS Care Compare: facility profiles and Care Compare ratings from
`dim_home_health_agency` and `dim_hospice`, patient-outcome and
process measures from `fct_home_health_quality`, hospice
Item-Set / Hospice Care Index measures from `fct_hospice_quality`,
and family-caregiver survey scores from `fct_hospice_cahps`. Every
view below reads a pre-aggregated source query — no per-agency or
per-hospice grain leaves the warehouse.

```sql hh_headline
select
    agencies,
    rated_agencies,
    avg_star_rating,
    states,
    offers_nursing_care,
    offers_physical_therapy,
    offers_occupational_therapy,
    offers_speech_pathology,
    offers_medical_social_services,
    offers_home_health_aide,
    provider_as_of,
    quality_as_of
from cms.home_health_stats
```

```sql hospice_headline
select
    hospices,
    states,
    hospices_with_cahps_star,
    avg_cahps_star,
    his_hci_measures,
    hospices_with_quality,
    provider_as_of,
    quality_as_of,
    cahps_as_of
from cms.hospice_stats
```

<BigValue data={hh_headline} value=agencies title="Home health agencies" fmt=num0 />
<BigValue data={hh_headline} value=avg_star_rating title="Avg quality-of-care stars" fmt=num2 />
<BigValue data={hospice_headline} value=hospices title="Hospice providers" fmt=num0 />
<BigValue data={hospice_headline} value=avg_cahps_star title="Avg CAHPS family-caregiver stars" fmt=num2 />

# Home health

## Reach and services offered

<Value data={hh_headline} column=agencies fmt=num0 /> Medicare-certified
home health agencies operate across
<Value data={hh_headline} column=states fmt=num0 /> states and
territories. Nursing care and the therapy services are near-universal
offerings; medical social services (
<Value data={hh_headline} column=offers_medical_social_services fmt=num0 />
of <Value data={hh_headline} column=agencies fmt=num0 /> agencies)
is the least common.

```sql hh_services
select 'Nursing care' as service,
    (select offers_nursing_care from cms.home_health_stats) as agencies
union all select 'Physical therapy',
    (select offers_physical_therapy from cms.home_health_stats)
union all select 'Occupational therapy',
    (select offers_occupational_therapy from cms.home_health_stats)
union all select 'Speech pathology',
    (select offers_speech_pathology from cms.home_health_stats)
union all select 'Home-health aide',
    (select offers_home_health_aide from cms.home_health_stats)
union all select 'Medical social services',
    (select offers_medical_social_services from cms.home_health_stats)
order by agencies desc
```

<BarChart
  data={hh_services}
  x=service
  y=agencies
  swapXY=true
  title="Home health agencies by service offered"
  yFmt=num0
/>

## Quality-of-patient-care star ratings

CMS assigns each agency a 1–5 quality-of-patient-care star rating in
half-star increments, computed from an OASIS-based composite. About
a third of agencies —
<Value data={hh_headline} column=agencies fmt=num0 /> minus
<Value data={hh_headline} column=rated_agencies fmt=num0 /> — are
unrated in the current vintage (usually too few completed episodes
for a stable score). Among rated agencies the distribution is roughly
symmetric around three stars.

```sql hh_star_distribution
select star_bracket, agencies
from cms.home_health_star_distribution
order by star_bracket
```

<BarChart
  data={hh_star_distribution}
  x=star_bracket
  y=agencies
  title="Home health agencies by star rating"
  yFmt=num0
/>

### By ownership

Non-profit agencies average the highest stars; government-operated
agencies — the smallest cohort — average the lowest. Proprietary
agencies dominate the population by a wide margin.

```sql hh_ownership
select
    ownership_type,
    agencies,
    rated_agencies,
    avg_star_rating
from cms.home_health_ownership_summary
order by avg_star_rating desc nulls last
```

<BarChart
  data={hh_ownership}
  x=ownership_type
  y=avg_star_rating
  swapXY=true
  title="Average quality-of-care stars by ownership type"
  yFmt=num2
/>

<DataTable data={hh_ownership} rows=10>
  <Column id=ownership_type title="Ownership" />
  <Column id=agencies title="Agencies" fmt=num0 />
  <Column id=rated_agencies title="Rated" fmt=num0 />
  <Column id=avg_star_rating title="Avg stars" fmt=num2 />
</DataTable>

## Selected quality measures vs national

Every row in `fct_home_health_quality` carries the CMS-published
national benchmark for its measure, so agency averages and the
national number are directly comparable within a measure. The
OASIS measures are all percentages (higher is better on the
"improve" measures; lower is better on `pressure_ulcer` and
`major_falls`). Averages below are unweighted across reporting
agencies, and on the improvement measures they run roughly 3–10
percentage points below the CMS-published national, which weights
by volume — smaller agencies with lower scores pull the
arithmetic mean down.

```sql hh_oasis_measures
select
    measure_code,
    measure_name,
    agencies_reporting,
    avg_score,
    national_value
from cms.home_health_quality_measures
where measure_source = 'oasis'
    and measure_code not in ('pressure_ulcer', 'major_falls')
order by national_value desc
```

<BarChart
  data={hh_oasis_measures}
  x=measure_code
  y={['avg_score', 'national_value']}
  swapXY=true
  type=grouped
  title="OASIS improvement / process measures (%): agency avg vs national"
  yFmt=num1
/>

Claims-based measures — discharge-to-community, potentially
preventable readmissions, and potentially preventable
hospitalizations — publish a national observed rate CMS uses as the
benchmark. Unweighted agency averages track the national closely on
readmissions and hospitalizations (within a tenth of a point) and
run about two and a half points above it on discharge-to-community.

```sql hh_claims_measures
select
    measure_code,
    measure_name,
    agencies_reporting,
    avg_score,
    national_value
from cms.home_health_quality_measures
where measure_source = 'claims'
order by avg_score desc
```

<DataTable data={hh_claims_measures} rows=5>
  <Column id=measure_code title="Code" />
  <Column id=measure_name title="Measure" wrap=true />
  <Column id=agencies_reporting title="Reporting" fmt=num0 />
  <Column id=avg_score title="Agency avg" fmt=num2 />
  <Column id=national_value title="National" fmt=num2 />
</DataTable>

# Hospice

## Reach

<Value data={hospice_headline} column=hospices fmt=num0 />
Medicare-certified hospice providers span
<Value data={hospice_headline} column=states fmt=num0 /> states and
territories. Hospice ownership is dominated by for-profit providers,
but the family-caregiver CAHPS star rating shifts materially by
ownership — non-profit hospices average roughly half a star higher
than for-profit hospices, and government hospices a full star
higher.

```sql hospice_ownership
select
    ownership_type,
    hospices,
    hospices_rated,
    avg_cahps_star
from cms.hospice_ownership_summary
order by hospices desc
```

<BarChart
  data={hospice_ownership}
  x=ownership_type
  y=hospices
  swapXY=true
  title="Hospices by ownership type"
  yFmt=num0
/>

<DataTable data={hospice_ownership} rows=10>
  <Column id=ownership_type title="Ownership" />
  <Column id=hospices title="Hospices" fmt=num0 />
  <Column id=hospices_rated title="Rated (CAHPS)" fmt=num0 />
  <Column id=avg_cahps_star title="Avg CAHPS stars" fmt=num2 />
</DataTable>

### Top states

```sql hospice_states
select state, hospices, for_profit_share
from cms.hospice_state_summary
order by hospices desc
limit 15
```

<DataTable data={hospice_states} rows=15>
  <Column id=state title="State" />
  <Column id=hospices title="Hospices" fmt=num0 />
  <Column id=for_profit_share title="For-profit share" fmt=pct0 />
</DataTable>

## CAHPS family-caregiver survey

The Consumer Assessment of Healthcare Providers and Systems (CAHPS)
Hospice Survey asks the primary caregiver of every hospice decedent
about their family member's care. CMS publishes a summary star
rating (1–5) plus top / middle / bottom-box percentages for seven
composite topics. Hospices with too few completed surveys are unrated
for the summary — that leaves
<Value data={hospice_headline} column=hospices_with_cahps_star fmt=num0 />
hospices with a numeric star.

```sql hospice_cahps_star_distribution
select star_bucket, hospices
from cms.hospice_cahps_star_distribution
order by star_bucket
```

<BarChart
  data={hospice_cahps_star_distribution}
  x=star_bucket
  y=hospices
  title="Hospices by CAHPS family-caregiver summary star rating"
  yFmt=num0
/>

### Top-box percentages vs national

The chart below reports the top-box ("always" / "definitely
recommend" / rated 9–10) share for each composite topic. National
CAHPS scores CMS publishes are the corresponding weighted top-box
percentage across all reporting hospices; unweighted agency averages
run within a point of them.

```sql hospice_cahps_composites
select
    measure_code,
    measure_name,
    hospices_reporting,
    avg_score,
    national_value
from cms.hospice_cahps_composites
order by avg_score desc
```

<BarChart
  data={hospice_cahps_composites}
  x=measure_code
  y={['avg_score', 'national_value']}
  swapXY=true
  type=grouped
  title="CAHPS top-box % by composite topic: hospice avg vs national"
  yFmt=num1
/>

<DataTable data={hospice_cahps_composites} rows=10>
  <Column id=measure_code title="Code" />
  <Column id=measure_name title="Topic (top-box wording)" wrap=true />
  <Column id=hospices_reporting title="Reporting" fmt=num0 />
  <Column id=avg_score title="Avg top-box %" fmt=num1 />
  <Column id=national_value title="National %" fmt=num1 />
</DataTable>

## Where hospice care is delivered

The Hospice Item Set (HIS) reports the share of hospice-care days
each provider delivered in each setting. Home is by far the most
common — hospices in the average deliver roughly two-thirds of care
days in the patient's home — with assisted-living and nursing
facilities the two most common institutional settings.

```sql hospice_care_settings
select
    measure_name,
    hospices_reporting,
    avg_pct_of_days
from cms.hospice_care_settings
order by avg_pct_of_days desc
```

<BarChart
  data={hospice_care_settings}
  x=measure_name
  y=avg_pct_of_days
  swapXY=true
  title="Average share of care days by setting (%)"
  yFmt=num1
/>

## Process-of-care compliance

HIS process measures track whether specific clinical processes were
completed at hospice admission — e.g. screening for pain, assessing
beliefs and values, screening for dyspnea. Every measure is a
percent-compliant rate; comparisons across measures are apples-to-
apples in units, but each addresses a different clinical process,
so read them as a set rather than aggregating.

```sql hospice_process_measures
select
    measure_code,
    measure_name,
    hospices_reporting,
    avg_score
from cms.hospice_process_measures
order by avg_score desc
```

<DataTable data={hospice_process_measures} rows=10>
  <Column id=measure_code title="Code" />
  <Column id=measure_name title="Process" wrap=true />
  <Column id=hospices_reporting title="Reporting" fmt=num0 />
  <Column id=avg_score title="Avg %" fmt=num1 />
</DataTable>

## Caveats

- **Snapshot vintage.** Home-health provider and quality data both
  come from the Care Compare snapshot as of
  <Value data={hh_headline} column=provider_as_of fmt=longdate />.
  Hospice provider data is as of
  <Value data={hospice_headline} column=provider_as_of fmt=longdate />,
  hospice provider-quality data as of
  <Value data={hospice_headline} column=quality_as_of fmt=longdate />,
  and hospice CAHPS as of
  <Value data={hospice_headline} column=cahps_as_of fmt=longdate />.
  Every figure above is a point-in-time snapshot — the marts don't
  carry facility-level history.
- **Unrated providers.** Roughly a third of home-health agencies
  and two thirds of hospices lack a numeric star in the current
  vintage; those rows drop out of the star averages but still count
  in facility totals. That skews averages toward providers with
  enough case volume to be rated.
- **Unweighted averages.** All averages weight each agency or
  hospice equally, regardless of episode / patient volume. CMS's
  published national benchmarks weight by volume, so the two are
  not the same number — and the gap is systematic, not noise: on
  the OASIS improvement measures, unweighted agency averages run
  roughly 3–10 percentage points below the CMS-weighted national
  because smaller agencies with lower scores pull the arithmetic
  mean down.
- **Score units vary within `fct_hospice_quality`.** The mart holds
  percentages, counts, denominators, index scores (0–10 for the
  Hospice Care Index composite), and per-beneficiary dollar amounts
  in a single `score_numeric` column, distinguished only by
  `measure_code`. This page never aggregates across measures in that
  fact — every chart above filters to a single measure family whose
  units are consistent.
- **`Not Available` vs `Not Applicable`.** Both CAHPS and
  provider-quality files carry text-shaped scores; suppressed
  numeric values arrive as `NULL` in `score_numeric` and are
  excluded from averages, while the raw `score` column preserves
  the sentinel so analysts can tell suppression apart from a
  measure that is not applicable to a given provider.
