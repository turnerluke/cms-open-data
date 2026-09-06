---
title: Prescribers
---

Who drives spending on the top Part D drugs? This page reads
pre-aggregated views over `fct_prescriber_drug_spending` (one row per
prescriber `npi` × brand × generic, ~28M rows — the raw grain never
leaves the warehouse). All dollar figures are **prescriber-billed drug
cost**: what pharmacies billed for the prescriptions a prescriber
wrote, before rebates — not net Part D program spending.

```sql headline
select
    total_rows,
    prescribers,
    drugs,
    total_drug_cost,
    total_claims,
    suppressed_beneficiary_share,
    dim_drug_orphan_share
from cms.prescriber_stats
```

<BigValue data={headline} value=prescribers title="Prescribers" fmt=num0 />
<BigValue data={headline} value=drugs title="Distinct drugs" fmt=num0 />
<BigValue data={headline} value=total_drug_cost title="Prescriber-billed drug cost" fmt=usd1b />
<BigValue data={headline} value=suppressed_beneficiary_share title="Rows with suppressed beneficiary counts" fmt=pct0 />

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
higher.

<DataTable data={specialty}>
  <Column id=prescriber_type title="Specialty" wrap=true />
  <Column id=prescribers title="Prescribers" fmt=num0 />
  <Column id=total_claims title="Claims" fmt=num0 />
  <Column id=total_drug_cost title="Billed cost" fmt=usd0 />
  <Column id=cost_per_claim title="$/claim" fmt=usd0 />
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

- **Single snapshot, no trend.** The prescriber mart is a single
  snapshot (calendar-2024 claims, vintage in the mart's `as_of`
  column) with no year column, so nothing on this page is a time
  series.
- **Small rows are suppressed entirely.** CMS removes prescriber-drug
  rows with fewer than 11 claims, so every row here has ≥ 11 claims,
  totals **undercount** true spending, and low-volume prescribers are
  invisible (which also inflates the top-1% shares slightly).
- **Beneficiary counts are unusable in aggregate.** `total_beneficiaries`
  is NULL (suppressed below 11) on
  <Value data={headline} column=suppressed_beneficiary_share fmt=pct1 />
  of rows, so this page never sums beneficiaries or computes
  per-beneficiary figures.
- **Star-marked spending rows aggregate brand and generic versions.**
  The Part D spending file star-marks drug names whose estimates
  aggregate brand and generic versions; staging strips the marker so
  every row here conforms to `dim_drug`
  (<Value data={headline} column=dim_drug_orphan_share fmt=pct1 /> of
  rows orphan, enforced by a dbt test) and the gross-spending
  comparison covers all
  <Value data={vs_match} column=top_drugs fmt=num0 /> top drugs — but
  an aggregated gross figure can overshoot its brand-only
  prescriber-billed counterpart, which is why Stelara's billed/gross
  ratio runs low.
- **Billed ≠ net.** Prescriber-billed drug cost ignores manufacturer
  rebates and DIR; actual net Part D spending is materially lower,
  especially for high-rebate brand drugs.
- **Specialty is self-reported.** `prescriber_type` comes from the
  provider's Medicare enrollment/claims specialty, with 182 distinct
  values of varying granularity (plus a negligible `Unknown` bucket —
  2 NPIs with no specialty on file).
