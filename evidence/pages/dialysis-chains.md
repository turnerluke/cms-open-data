---
title: Dialysis chains
---

Two operators — DaVita and Fresenius Medical Care — run a combined
<Value data={overview} column=duopoly_share fmt=pct1 /> of every
Medicare-certified outpatient dialysis facility in the United States.
Do the national chains deliver measurably different quality than the
rest of the market, or is the duopoly's dominance a story about
capital and scale alone? This page compares four `chain_group`s —
DaVita, Fresenius, Other chain, and Independent — across the CMS Care
Compare quality file. The comparison is observational, cross-sectional,
and unadjusted for patient case-mix beyond the risk adjustment CMS
already applies to its standardized-ratio measures; see the limitations
before drawing sharp conclusions.

```sql overview
select
    total_facilities,
    davita_facilities,
    fresenius_facilities,
    other_chain_facilities,
    independent_facilities,
    other_chain_orgs,
    duopoly_facilities,
    duopoly_share,
    as_of
from cms.dialysis_chain_overview
```

<BigValue data={overview} value=davita_facilities title="DaVita facilities" fmt=num0 />
<BigValue data={overview} value=fresenius_facilities title="Fresenius facilities" fmt=num0 />
<BigValue data={overview} value=other_chain_facilities title="Other chain" fmt=num0 />
<BigValue data={overview} value=independent_facilities title="Independent" fmt=num0 />

## Method

The four `chain_group` buckets collapse the 32 distinct chain-organization
labels in `dim_dialysis_facility` into an analytical grouping:

- **DaVita** and **Fresenius** are the two national chains (chain
  organization values `DaVita` and `Fresenius Medical Care`).
- **Other chain** rolls up the remaining
  <Value data={overview} column=other_chain_orgs fmt=num0 /> regional
  chain organizations
  (`is_chain_owned = true` but not DaVita or Fresenius).
- **Independent** is `is_chain_owned = false` — CMS labels these
  facilities with the literal chain value `Independent`.

Every score aggregation in `fct_dialysis_chain_measure` filters to
`is_reported = true` (CMS availability code `001`) — suppressed rows
carry a `NULL` score and are excluded, not zeroed. The chain-measure
mart carries two mean flavours: `score_unweighted_mean` gives each
facility one vote (answering *what does the typical facility in this
chain look like?*), while `score_weighted_mean` weights by the reported
denominator — patients, patient-months, or hospitalizations — and
answers *what does the typical patient at this chain experience?* For
five-star, SIR, and the healthcare-worker vaccination measure CMS does
not publish a per-row denominator, so only the unweighted mean is
available.

## Star mix, alongside the unrated share

CMS assigns each dialysis facility a 1–5 star rating in whole-star
increments — but only if the facility clears CMS's minimum-volume and
data-availability thresholds. Facilities that fall short are
**unrated**, and unrated share differs enormously across the four
chain groups. Any comparison of mean stars that silently drops unrated
facilities understates the gap.

```sql star_summary
select
    chain_group,
    chain_sort,
    n_facilities_total,
    n_rated,
    n_unrated,
    unrated_share,
    mean_star_rated
from cms.dialysis_chain_star_summary
order by chain_sort
```

<DataTable data={star_summary}>
  <Column id=chain_group title="Chain group" />
  <Column id=n_facilities_total title="Facilities" fmt=num0 />
  <Column id=n_rated title="Rated" fmt=num0 />
  <Column id=n_unrated title="Unrated" fmt=num0 />
  <Column id=unrated_share title="Unrated share" fmt=pct1 />
  <Column id=mean_star_rated title="Mean stars (rated only)" fmt=num2 />
</DataTable>

Among rated facilities the four groups spread across roughly three
quarters of a star. Once the unrated bucket is drawn in, the picture
gets sharper: Independent facilities are unrated at roughly ten times
the DaVita/Fresenius rate, so the "mean stars" column above is
computed on a much smaller — and self-selected — slice of the
Independent population.

```sql star_mix
select chain_group, chain_sort, star_bucket, sort_order, facilities, share
from cms.dialysis_chain_star_mix
```

<BarChart
  data={star_mix}
  x=chain_group
  y=facilities
  series=star_bucket
  type=stacked
  title="Star-rating distribution by chain group (facilities)"
  sort=false
  yFmt=num0
/>

<BarChart
  data={star_mix}
  x=chain_group
  y=share
  series=star_bucket
  type=stacked100
  title="Star-rating distribution by chain group (share)"
  sort=false
  yFmt=pct0
/>

## Four clinical measures where the gap is largest

The measures below are drawn from `fct_dialysis_chain_measure`. SIR
(standardized infection ratio) is the CMS-flagship outcome; the other
three are percent-of-patient process/intermediate-outcome measures
that consistently split by chain group in the same direction. For SIR
and the other standardized ratios lower is better; for fistula use
higher is better; for long-term catheter use and low hemoglobin lower
is better.

```sql key_measures
select
    measure_code,
    measure_sort,
    measure_name,
    chain_group,
    chain_sort,
    denominator_unit,
    n_facilities_reported,
    n_facilities_total,
    reporting_rate,
    score_unweighted_mean,
    score_weighted_mean,
    total_denominator
from cms.dialysis_chain_key_measures
```

<BarChart
  data={key_measures}
  x=chain_group
  y=score_unweighted_mean
  series=measure_code
  type=grouped
  title="Facility-vote mean by chain group (measure_code)"
  sort=false
  yFmt=num2
/>

<DataTable data={key_measures} groupBy=measure_name groupType=section>
  <Column id=chain_group title="Chain group" />
  <Column id=reporting_rate title="Reporting rate" fmt=pct1 />
  <Column id=n_facilities_reported title="Reporting" fmt=num0 />
  <Column id=score_unweighted_mean title="Facility-vote mean" fmt=num2 />
  <Column id=score_weighted_mean title="Patient-vote mean" fmt=num2 />
  <Column id=total_denominator title="Denominator (patients / patient-months)" fmt=num0 />
</DataTable>

Facility-vote and patient-vote means agree to within about a
percentage point on the high-participation measures (fistula, catheter,
`hgb<10`) — chain-averaged facility performance does not appear to be
driven by a handful of very large facilities. The two flavours diverge
where a few large reporters dominate; the mart surfaces both so the
reader can inspect which is which without going back to the fact
grain.

## SIR: category distribution and the reporting gap

CMS labels each SIR-reporting facility "Better than Expected", "As
Expected", or "Worse than Expected" using confidence-interval overlap
with 1.0, and marks the suppressed rows "Not Available". Displaying
all four categories side by side per chain shows both the outcome
distribution and the reporting gap in one visual.

```sql sir_categories
select chain_group, chain_sort, category, category_sort, facilities
from cms.dialysis_chain_sir_categories
```

<BarChart
  data={sir_categories}
  x=chain_group
  y=facilities
  series=category
  type=stacked
  title="Standardized infection ratio: facility categorization by chain"
  sort=false
  yFmt=num0
/>

The `Not Available` bucket is where the selection story lives:
Independent facilities are far more likely to fall into it than either
national chain, and every "better/worse than expected" count above
excludes those facilities from the denominator.

## Reporting rates across every measure

The full chain × measure reporting-rate view. It complicates the
selection story in an important way: reporting selectivity runs in
*both* directions. On the claims-derived ratios and access measures
highlighted above, Independent facilities report far less often than
the chains. But on the lab-derived family — Kt/V, the serum-phosphorus
bands, hypercalcemia, nPCR — the pattern inverts: DaVita reports those
for under 1% of its facilities while Independent facilities report
them at roughly 75–83%. On 11 of the 27 measures the Independent
reporting rate is *higher* than DaVita's. No single chain group sees
the full measure set, so each comparison should be read against its
own reporting-rate row, not a blanket assumption about who reports.
(The `hcp_vaccination` row is the extreme point: Fresenius reports it
for only 3 of its 2,701 facilities in the current vintage, so the
mean there is not comparable across chains.)

```sql reporting_rates
select
    measure_code,
    measure_name,
    chain_group,
    reporting_rate,
    n_facilities_reported,
    n_facilities_total
from cms.dialysis_chain_reporting_rates
```

<DataTable data={reporting_rates} rows=27 groupBy=measure_name groupType=section>
  <Column id=chain_group title="Chain group" />
  <Column id=reporting_rate title="Reporting rate" fmt=pct1 />
  <Column id=n_facilities_reported title="Reporting" fmt=num0 />
  <Column id=n_facilities_total title="Facilities" fmt=num0 />
</DataTable>

## Limitations

The observed gaps are real in the CMS vintage as of
<Value data={overview} column=as_of fmt=longdate />, but four caveats
substantially condition how far they can be pushed.

- **Selection bias in the Independent cohort.** About
  <Value data={overview} column=independent_facilities fmt=num0 />
  Independent facilities are in the population, but only a fraction
  clear CMS's reporting thresholds on the ratio and access measures
  highlighted above (43% for SIR, versus 91–93% at the two national
  chains). A standard concern with voluntary-threshold reporting is
  that non-reporters skew small and new — the facilities most at
  risk of weaker outcomes — which would make the observed chain vs
  Independent gap on those measures partly a comparison of the
  survivors rather than of the full populations. The warehouse
  cannot test that directly, so treat the Independent means on
  low-reporting measures as the reported cohort's average, not the
  cohort-wide one. (As the reporting-rate table shows, selectivity
  is not one-sided: the chains barely report the lab-derived
  measures that Independents report at 75–83%.)
- **Standardized ratios are risk-adjusted; stars and percent measures
  are not.** SIR, SMR, SHR, SRR, and the other ratios divide observed
  events by CMS-modeled expected events based on facility case-mix
  (age, comorbidities, dialysis vintage, etc.), so a low ratio at a
  chain does not simply reflect a healthier patient panel. But the
  overall five-star composite and the percent-family measures
  (long-term catheter, `hgb<10`, fistula) are *not* risk-adjusted for
  patient-mix differences across chains. A chain that treats a
  healthier patient panel on average will score better on the
  percent-family measures for reasons that have nothing to do with
  care quality.
- **Cross-sectional, single vintage, no causal claim.** The chain
  marts are a point-in-time snapshot as of
  <Value data={overview} column=as_of fmt=longdate />. Nothing here
  is a time series, and nothing here identifies a mechanism by which
  chain affiliation would affect outcomes (protocol standardization,
  purchasing power, staffing ratios, patient selection). Differences
  between chain groups are associations, not effects.
- **Facility count ≠ patient count.** DaVita, Fresenius, Other chain,
  and Independent facilities differ in station count and patient
  panel size. The unweighted (facility-vote) mean gives every facility
  one vote regardless of size; the weighted (patient-vote) mean
  weights each facility by its reported denominator. The two agree
  closely on high-participation measures and can diverge where a few
  large reporters dominate — inspect both columns in the tables above
  when the sign or magnitude matters.

## Caveats

- **Snapshot vintage.** Every figure above is drawn from the Care
  Compare snapshot as of
  <Value data={overview} column=as_of fmt=longdate />. The chain
  marts are cross-sectional and do not carry a facility-level or
  chain-level history — chain affiliation itself can change (a
  facility acquired by DaVita between vintages moves buckets).
- **Reported-only aggregation.** Every mean and category count above
  filters `fct_dialysis_chain_measure` to `is_reported = true`
  (availability code `001`); suppressed rows are excluded, not zeroed.
  The `Not Available` category on the standardized-ratio family is
  the count of suppressed rows carried through as its own bucket.
- **Weighted means unavailable on three measures.** CMS ships no
  per-row denominator for `five_star`, `sir`, or `hcp_vaccination`,
  so `score_weighted_mean` is `NULL` for those measures and the
  facility-vote mean is the only chain summary available. The
  patient-vote column in the key-measures table is blank in the SIR
  row for that reason.
- **`Other chain` is a long tail, not a single operator.** The
  bucket rolls up
  <Value data={overview} column=other_chain_orgs fmt=num0 /> distinct
  chain organizations spanning a large size range — the largest
  regional operator in the current vintage runs several hundred
  facilities, the smallest chains have just one or two. Read that
  column as an aggregate reference point, not as a homogeneous
  competitor to the national duopoly.
- **Chain-group definition lives in one macro.** The `chain_group`
  buckets are computed by the `dialysis_chain_group` dbt macro and
  materialized in `dim_dialysis_chain`, so every chain-comparison
  view on this page (and every future one) agrees by construction.
