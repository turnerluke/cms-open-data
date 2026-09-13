---
title: Prescribers
---

Who drives spending on the top Part D drugs? This page reads three
pre-aggregated marts. Prescriber-level totals come from
`fct_prescriber_profile` (one row per NPI, no drug-level suppression).
The prescriber × drug detail lives in `fct_prescriber_drug_spending`
(~28M rows), which CMS strips of any row with fewer than 11 claims —
so its aggregate totals sit about 13.5% below the profile file's on
claims and 21% below on dollars. National and state-level rankings
come from `fct_drug_geography`. All dollar figures are **prescriber-
billed drug cost**: what pharmacies billed for the prescriptions a
prescriber wrote, before rebates — not net Part D program spending.

```sql profile_overview
select
    prescribers,
    individuals,
    organizations,
    total_claims,
    total_drug_cost,
    suppressed_beneficiary_share
from cms.prescriber_profile_overview
```

```sql headline
select
    total_rows,
    prescribers as detail_prescribers,
    drugs,
    total_drug_cost as detail_drug_cost,
    total_claims as detail_claims,
    dim_drug_orphan_share
from cms.prescriber_stats
```

<BigValue data={profile_overview} value=prescribers title="Prescribers" fmt=num0 />
<BigValue data={headline} value=drugs title="Distinct drugs" fmt=num0 />
<BigValue data={profile_overview} value=total_drug_cost title="Prescriber-billed drug cost" fmt=usd1b />
<BigValue data={profile_overview} value=total_claims title="Prescriber-billed claims" fmt=num0 />
<BigValue data={profile_overview} value=suppressed_beneficiary_share title="NPIs with suppressed beneficiary count" fmt=pct0 />

## Top drugs by prescriber-billed cost

```sql top_drugs
select
    brand_name,
    generic_name,
    prescribers,
    total_claims,
    total_drug_cost,
    cost_per_claim
from cms.prescriber_top_drugs
order by total_drug_cost desc
limit 15
```

<BarChart
  data={top_drugs}
  x=brand_name
  y=total_drug_cost
  swapXY=true
  title="Top 15 drugs by prescriber-billed cost"
  yFmt=usd1b
/>

The list splits into two regimes: mass-market drugs written by
hundreds of thousands of prescribers at a few hundred dollars per
claim (anticoagulants, GLP-1s), and specialty drugs written by a few
thousand prescribers at five figures per claim.

<DataTable data={top_drugs}>
  <Column id=brand_name title="Brand" />
  <Column id=generic_name title="Generic" wrap=true />
  <Column id=prescribers title="Prescribers" fmt=num0 />
  <Column id=total_claims title="Claims" fmt=num0 />
  <Column id=total_drug_cost title="Billed cost" fmt=usd0 />
  <Column id=cost_per_claim title="$/claim" fmt=usd0 />
</DataTable>

## Claim leaders vs cost leaders

The two rankings above hide the fact that no drug is both a top-10
claim leader and a top-10 cost leader. `fct_drug_geography` National
rows make this concrete: the ten drugs written for the most claims —
generic statins, antihypertensives, thyroid hormone — cost only a few
dollars per claim. The ten drugs that drive the most spending —
anticoagulants, GLP-1s, immunomodulators, an oncology brand — average
hundreds to tens of thousands of dollars per claim.

```sql rank_split
select
    top10_claims_claim_share,
    top10_claims_cost_share,
    top10_cost_claim_share,
    top10_cost_cost_share,
    overlap_top10
from cms.drug_geography_rank_split
```

The top 10 by claim volume account for
<Value data={rank_split} column=top10_claims_claim_share fmt=pct1 />
of all Part D claims on the geography file but only
<Value data={rank_split} column=top10_claims_cost_share fmt=pct1 />
of its drug cost. The top 10 by drug cost account for
<Value data={rank_split} column=top10_cost_claim_share fmt=pct1 /> of
claims but
<Value data={rank_split} column=top10_cost_cost_share fmt=pct1 /> of
cost. The two lists overlap on
<Value data={rank_split} column=overlap_top10 fmt=num0 /> drugs.

```sql claim_leaders
select
    brand_name,
    generic_name,
    total_prescribers,
    total_claims,
    total_drug_cost,
    cost_per_claim
from cms.drug_geography_claim_leaders
order by total_claims desc
```

```sql cost_leaders
select
    brand_name,
    generic_name,
    total_prescribers,
    total_claims,
    total_drug_cost,
    cost_per_claim
from cms.drug_geography_cost_leaders
order by total_drug_cost desc
```

<BarChart
  data={claim_leaders}
  x=brand_name
  y=total_claims
  swapXY=true
  title="Top 10 by claim volume — average a few dollars per claim"
  yFmt=num0
/>

<BarChart
  data={cost_leaders}
  x=brand_name
  y=total_drug_cost
  swapXY=true
  title="Top 10 by drug cost — average hundreds to tens of thousands per claim"
  yFmt=usd1b
/>

<DataTable data={cost_leaders}>
  <Column id=brand_name title="Brand" />
  <Column id=generic_name title="Generic" wrap=true />
  <Column id=total_prescribers title="Prescribers" fmt=num0 />
  <Column id=total_claims title="Claims" fmt=num0 />
  <Column id=total_drug_cost title="Billed cost" fmt=usd0 />
  <Column id=cost_per_claim title="$/claim" fmt=usd0 />
</DataTable>

## How concentrated is each top drug?

For each of the top 25 drugs, the share of its billed cost written by
its top 1% of prescribers (by cost; the 1% headcount is rounded up, so
every drug keeps at least one). Spending on the biggest drugs is
**not** dominated by a handful of prescribers:

```sql concentration
select
    brand_name,
    generic_name,
    prescribers,
    top_1pct_prescribers,
    total_drug_cost,
    top_1pct_cost_share
from cms.prescriber_drug_concentration
order by top_1pct_cost_share desc
```

```sql top_drug_row
select
    brand_name,
    prescribers,
    top_1pct_prescribers,
    total_drug_cost,
    top_1pct_cost_share
from cms.prescriber_drug_concentration
order by total_drug_cost desc
limit 1
```

For <Value data={top_drug_row} column=brand_name /> — the biggest drug
at <Value data={top_drug_row} column=total_drug_cost fmt=usd1b /> —
the top 1% of its
<Value data={top_drug_row} column=prescribers fmt=num0 /> prescribers
(<Value data={top_drug_row} column=top_1pct_prescribers fmt=num0 />
prescribers) account for
<Value data={top_drug_row} column=top_1pct_cost_share fmt=pct1 /> of
its billed cost. Across the top 25 drugs the top-1% share stays in
the single digits to mid-teens — broad prescribing bases, not a few
outlier clinics, drive these totals. (Because CMS drops
prescriber-drug rows under 11 claims, the smallest prescribers are
missing from the denominator, which nudges these shares upward.)

<BarChart
  data={concentration}
  x=brand_name
  y=top_1pct_cost_share
  swapXY=true
  title="Share of billed cost from the top 1% of prescribers"
  yFmt=pct0
/>

## Which specialties drive the spending?

```sql specialty
select
    prescriber_type,
    prescribers,
    total_claims,
    total_drug_cost,
    cost_per_claim
from cms.prescriber_specialty_spending
order by total_drug_cost desc
limit 15
```

<BarChart
  data={specialty}
  x=prescriber_type
  y=total_drug_cost
  swapXY=true
  title="Top 15 specialties by prescriber-billed cost"
  yFmt=usd1b
/>

Primary care (nurse practitioners, internal medicine, family practice,
physician assistants) bills the most in aggregate through sheer claim
volume, while oncology and rheumatology reach the top ten with a tiny
fraction of the claims — their cost per claim runs roughly 5–30×
higher. Both cost and claim totals here come from the sub-11-claim-
suppressed detail file, so they undercount every specialty (13.5% of
claims and 21% of cost are missing at the file level); the profile-
file view in the next section aligns to the full $288B and adds a
brand / opioid / antibiotic / antipsychotic breakdown.

<DataTable data={specialty}>
  <Column id=prescriber_type title="Specialty" wrap=true />
  <Column id=prescribers title="Prescribers" fmt=num0 />
  <Column id=total_claims title="Claims" fmt=num0 />
  <Column id=total_drug_cost title="Billed cost" fmt=usd0 />
  <Column id=cost_per_claim title="$/claim" fmt=usd0 />
</DataTable>

## Prescriber-type prescribing patterns

Same specialties, but from `fct_prescriber_profile` — one row per NPI,
no drug-level suppression — so both the totals and the mix columns
cover every prescribing NPI, not just those with 11+ claims on a
given drug. Restricted to types with at least 5,000 prescribers so
the rate columns are stable. Rates are computed only over rows where
CMS didn't blank the numerator (opioid, antibiotic, and antipsychotic-
GE65 measures are individually suppressed when their counts are 1–10).
`prescriber_type` here comes directly from the profile file — the FK
to `dim_clinician` is intentionally not used, since only ~66% of NPIs
match the clinician roster.

```sql type_profile
select
    prescriber_type,
    prescribers,
    total_claims,
    total_drug_cost,
    cost_per_claim,
    brand_share,
    opioid_rate,
    antibiotic_rate,
    antipsychotic_ge65_rate
from cms.prescriber_type_profile
order by total_drug_cost desc
```

<BarChart
  data={type_profile}
  x=prescriber_type
  y=brand_share
  swapXY=true
  title="Brand-name share of claims by specialty"
  yFmt=pct0
/>

The single highest brand share in the chart belongs to Pharmacists
(~69%) — an unusual category whose Part D claims skew toward
specialty dispensing rather than office practice. Among physician
specialties, Pulmonary Disease (~50%), Endocrinology (~48%),
Ophthalmology (~36%, with Optometry slightly higher at ~39%), and
Infectious Disease (~26%) prescribe from brand-heavy therapeutic
areas (inhalers, GLP-1s / insulins, ophthalmic biologics, and HIV
regimens respectively). Primary-care specialties sit near 10–13% brand
by claim.

<BarChart
  data={type_profile}
  x=prescriber_type
  y=antibiotic_rate
  swapXY=true
  title="Antibiotic share of claims by specialty"
  yFmt=pct0
/>

Antibiotic prescribing is dominated by three specialties that make
sense clinically: Infectious Disease (~31% of claims), Urology
(~16%), and Dermatology (~10%). Primary-care antibiotic rates run
around 3–7% (Physician Assistants highest at ~7%, Family Practice
lowest at ~3%).

<BarChart
  data={type_profile}
  x=prescriber_type
  y=antipsychotic_ge65_rate
  swapXY=true
  title="Antipsychotic (age 65+) share of claims by specialty"
  yFmt=pct0
/>

Psychiatry accounts for ~8% of its claim volume in antipsychotics
prescribed to beneficiaries 65 and older — an order of magnitude above
every other specialty. Neurology (~2%) and Nurse Practitioners (~2%)
sit next; the rest are below 1%.

<DataTable data={type_profile} rows=20>
  <Column id=prescriber_type title="Specialty" wrap=true />
  <Column id=prescribers title="Prescribers" fmt=num0 />
  <Column id=total_claims title="Claims" fmt=num0 />
  <Column id=total_drug_cost title="Billed cost" fmt=usd0 />
  <Column id=cost_per_claim title="$/claim" fmt=usd0 />
  <Column id=brand_share title="Brand share" fmt=pct1 />
  <Column id=opioid_rate title="Opioid" fmt=pct2 />
  <Column id=antibiotic_rate title="Antibiotic" fmt=pct2 />
  <Column id=antipsychotic_ge65_rate title="Antipsy. 65+" fmt=pct2 />
</DataTable>

## Where is the spending written?

```sql states
select
    state,
    prescribers,
    total_drug_cost,
    cost_per_prescriber
from cms.prescriber_state_spending
order by total_drug_cost desc
limit 10
```

<BarChart
  data={states}
  x=state
  y=total_drug_cost
  title="Top 10 states by prescriber-billed cost"
  yFmt=usd1b
/>

State totals track population; the `state` column also carries
territories and military/unknown codes, which is why there are more
than 51 values in the source.

## State cost-per-beneficiary variation

Aggregate state spending mostly tracks population, but *per-beneficiary*
cost varies more than the aggregate totals suggest — especially on
specialty drugs. This chart walks the biggest drug (Eliquis) across
the 50 states + DC, with the national cost-per-beneficiary marked as
a reference line. `fct_drug_geography` carries the national benchmark
inline on every state row, so the reference value doesn't require a
separate roll-up.

```sql eliquis_by_state
select
    state,
    total_prescribers,
    total_beneficiaries,
    cost_per_beneficiary,
    national_cost_per_beneficiary,
    share_of_national_cost
from cms.drug_geography_eliquis_by_state
order by cost_per_beneficiary desc
```

```sql eliquis_nat
select max(national_cost_per_beneficiary) as national_cpb
from cms.drug_geography_eliquis_by_state
```

<BarChart
  data={eliquis_by_state}
  x=state
  y=cost_per_beneficiary
  title="Eliquis cost per beneficiary by state (national benchmark shown)"
  yFmt=usd0
>
  <ReferenceLine
    y={eliquis_nat[0].national_cpb}
    label="National"
    labelPosition=aboveEnd
  />
</BarChart>

Even the largest drug — where per-patient dosing is nearly identical
by protocol — shows a
<Value data={eliquis_nat} column=national_cpb fmt=usd0 /> national
per-beneficiary figure that varies from about $3,378 (DC) to $4,743
(Connecticut), a 1.40× spread across states. The higher-priced
specialty drugs stretch that spread further. This table lists the
top-25 national-cost drugs sorted by their state max/min ratio; the
biggest per-beneficiary geographic differences show up on
immunomodulators, oral oncology agents, and rare-disease biologics.

```sql state_spread
select
    brand_name,
    generic_name,
    national_cost,
    national_cost_per_beneficiary,
    min_state_cost_per_beneficiary,
    max_state_cost_per_beneficiary,
    max_min_ratio,
    states_reporting
from cms.drug_geography_state_spread
order by max_min_ratio desc
```

<DataTable data={state_spread}>
  <Column id=brand_name title="Brand" />
  <Column id=generic_name title="Generic" wrap=true />
  <Column id=national_cost title="National $" fmt=usd0 />
  <Column id=national_cost_per_beneficiary title="National $/ben." fmt=usd0 />
  <Column id=min_state_cost_per_beneficiary title="Min state $/ben." fmt=usd0 />
  <Column id=max_state_cost_per_beneficiary title="Max state $/ben." fmt=usd0 />
  <Column id=max_min_ratio title="Max / min" fmt=num2 />
  <Column id=states_reporting title="States" fmt=num0 />
</DataTable>

State-level `total_beneficiaries` is suppressed on about 19% of state
rows (CMS blanks counts of 1–10), so tiny (drug × state) cells drop
out of the per-beneficiary column — this filter alone excludes the
territories and armed-forces pseudo-codes that would otherwise skew
the min/max. The four missing drug-state cells in the table — Montana
and Wyoming for Vyndamax, Wyoming for Pomalyst and Ofev — are the
ones where CMS suppressed the state's beneficiary count for that
drug.

## Top prescriber-drug combinations

The largest single prescriber×drug lines among the top 25 drugs. Even
the biggest individual line is a small sliver of its drug's total —
the `share_of_drug_cost` column makes the concentration story above
concrete.

```sql leaders
select
    prescriber_name,
    prescriber_type,
    city,
    state,
    brand_name,
    total_claims,
    total_drug_cost,
    share_of_drug_cost
from cms.prescriber_drug_leaders
order by total_drug_cost desc
limit 20
```

<DataTable data={leaders}>
  <Column id=prescriber_name title="Prescriber" wrap=true />
  <Column id=prescriber_type title="Specialty" wrap=true />
  <Column id=city title="City" />
  <Column id=state title="State" />
  <Column id=brand_name title="Drug" />
  <Column id=total_claims title="Claims" fmt=num0 />
  <Column id=total_drug_cost title="Billed cost" fmt=usd0 />
  <Column id=share_of_drug_cost title="Share of drug" fmt=pct2 />
</DataTable>

## Prescriber-billed vs gross Part D spending

The top 25 drugs joined to `fct_part_d_drug_spending`'s
manufacturer-roll-up gross spending for the same drug, via `drug_key`
(exact upper-cased brand + generic match; staging strips the Part D
spending file's trailing-`*` aggregate marker, so the names line up).

```sql vs_match
select
    count(*) as top_drugs,
    count(part_d_total_spending) as matched,
    max(part_d_spending_year) as part_d_year
from cms.prescriber_vs_part_d
```

<Value data={vs_match} column=matched fmt=num0 /> of
<Value data={vs_match} column=top_drugs fmt=num0 /> top drugs match a
<Value data={vs_match} column=part_d_year fmt=id /> gross-spending
row. Prescriber-billed cost lands at roughly 80–96% of gross Part D
spending for most drugs — consistent with the prescriber file
dropping sub-11-claim rows and covering a slightly narrower claim
universe. Stelara sits lower (~67%): its gross-spending row is one
CMS star-marked as aggregating brand and generic versions, while the
billed figure covers only rows the prescriber file names `Stelara`.
Neither figure is net of rebates.

```sql vs_part_d
select
    brand_name,
    generic_name,
    prescriber_billed_cost,
    part_d_total_spending,
    billed_to_gross_ratio
from cms.prescriber_vs_part_d
where part_d_total_spending is not null
order by prescriber_billed_cost desc
```

<DataTable data={vs_part_d}>
  <Column id=brand_name title="Brand" />
  <Column id=generic_name title="Generic" wrap=true />
  <Column id=prescriber_billed_cost title="Prescriber-billed" fmt=usd0 />
  <Column id=part_d_total_spending title="Part D gross" fmt=usd0 />
  <Column id=billed_to_gross_ratio title="Billed / gross" fmt=pct0 />
</DataTable>

## Caveats

- **Single snapshot, no trend.** All three marts are single snapshots
  (calendar-2024 claims, vintage in each mart's `as_of` column) with
  no year column, so nothing on this page is a time series.
- **Small rows are suppressed entirely.** CMS removes prescriber-drug
  rows with fewer than 11 claims from the detail file, so every row
  in the detail-file sections has ≥ 11 claims, totals **undercount**
  true spending (by ~13.5% of claims and ~21% of dollars vs the
  profile mart), and low-volume prescribers are invisible on the
  detail file (which also inflates the top-1% shares slightly). The
  profile mart itself has no such row filter — CMS only drops NPIs
  with 10 or fewer total claims from that file — so the aggregate
  totals in the headline BigValues and the prescriber-type-patterns
  section include those small prescriber-drug lines.
- **Measure-level suppression on the profile file.** `total_beneficiaries`
  is NULL (suppressed at 1–10) on
  <Value data={profile_overview} column=suppressed_beneficiary_share fmt=pct1 />
  of profile NPIs; the opioid, antibiotic, and antipsychotic-GE65
  measures are individually NULL when their own counts fall in that
  band. The prescriber-type-patterns section computes each rate only
  over rows where the numerator is populated, so denominators shrink
  from row to row.
- **Geography state cells drop out too.** In `fct_drug_geography`,
  `total_beneficiaries` is NULL on ~19% of State rows, which is why
  the state cost-per-beneficiary charts show 51 states for Eliquis
  but only 49–50 for Vyndamax / Pomalyst / Ofev.
- **Star-marked spending rows aggregate brand and generic versions.**
  The Part D spending file star-marks drug names whose estimates
  aggregate brand and generic versions; staging strips the marker so
  every row here conforms to `dim_drug`
  (<Value data={headline} column=dim_drug_orphan_share fmt=pct1 /> of
  detail-file rows orphan, enforced by a dbt test) and the gross-
  spending comparison covers all
  <Value data={vs_match} column=top_drugs fmt=num0 /> top drugs — but
  an aggregated gross figure can overshoot its brand-only
  prescriber-billed counterpart, which is why Stelara's billed/gross
  ratio runs low.
- **Billed ≠ net.** Prescriber-billed drug cost ignores manufacturer
  rebates and DIR; actual net Part D spending is materially lower,
  especially for high-rebate brand drugs.
- **Specialty is self-reported.** `prescriber_type` comes from the
  provider's Medicare enrollment/claims specialty. The detail file
  carries 182 distinct values; the profile file carries 214 (with 2
  NPIs missing a specialty). Both files' organizational NPIs (2 rows
  in the profile) are omitted from the `dim_clinician` relationships
  test rather than reported as orphans.
