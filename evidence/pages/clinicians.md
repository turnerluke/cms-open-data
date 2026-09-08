---
title: Clinicians and industry payments
---

Open Payments' 2024 general-payment file — a manufacturer- and
GPO-reported record of every transfer of value to a US physician,
advanced-practice provider, dentist, or teaching hospital — joined to
the clinician roster from `dim_clinician`, Part B utilization from
`fct_physician_utilization`, and Part D prescribing from
`fct_prescriber_drug_spending`. Every chart below reads a
pre-aggregated source query; the 15.5M-record raw fact never leaves
the warehouse. Payment payers are always rolled up on
`paying_manufacturer_or_gpo_id`, never on raw name, so the same
manufacturer under mixed-case filings collapses to one row.

```sql headline
select
    records,
    total_dollars,
    paid_npis,
    paying_entities,
    payment_year,
    dim_clinician_orphan_share,
    food_beverage_record_share,
    food_beverage_dollar_share,
    as_of
from cms.clinician_payment_stats
```

<BigValue data={headline} value=total_dollars title="Total industry payments (2024)" fmt=usd1b />
<BigValue data={headline} value=paid_npis title="Paid clinicians (NPIs)" fmt=num0 />
<BigValue data={headline} value=records fmt=num0 title="General-payment records" />
<BigValue data={headline} value=paying_entities fmt=num0 title="Paying manufacturers / GPOs" />

## How concentrated are the dollars?

Two thirds of every industry dollar reaches only the top 1% of paid
clinicians, and 90% stops with the top 10%. The bottom half of the
paid population combined receives a rounding-error share.

```sql concentration
select
    bucket,
    top_share,
    clinicians
from cms.clinician_payment_concentration
```

<BarChart
  data={concentration}
  x=bucket
  y=top_share
  title="Share of 2024 industry-payment dollars going to the top-N% of paid clinicians"
  yFmt=pct0
/>

<DataTable data={concentration}>
  <Column id=bucket title="Cohort" />
  <Column id=clinicians title="Clinicians" fmt=num0 />
  <Column id=top_share title="Share of $" fmt=pct1 />
</DataTable>

Looked at the other way — by absolute dollar bracket per clinician —
about 83% of paid NPIs receive under $1,000 across all of 2024
combined, and 4,132 (0.4%) cross $100,000. Those 4,132 clinicians
account for the bulk of the total.

```sql brackets
select
    bracket,
    clinicians,
    dollars,
    dollar_share
from cms.clinician_payment_brackets
```

<BarChart
  data={brackets}
  x=bracket
  y=clinicians
  title="Paid clinicians by total 2024 industry payments received"
  yFmt=num0
/>

<DataTable data={brackets}>
  <Column id=bracket title="2024 total received" />
  <Column id=clinicians title="Clinicians" fmt=num0 />
  <Column id=dollars title="Dollars in bracket" fmt=usd0 />
  <Column id=dollar_share title="Share of total $" fmt=pct1 />
</DataTable>

## The Food-and-Beverage paradox

<Value data={headline} column=food_beverage_record_share fmt=pct1 /> of
all 2024 general-payment records are `Food and Beverage` — the
per-attendee meal entries manufacturers file after promotional
lunches — but they account for only
<Value data={headline} column=food_beverage_dollar_share fmt=pct1 />
of the dollars. The dollar totals live in a handful of rare
categories: royalties and licenses, consulting, and speaker
compensation.

```sql nature
select
    nature_of_payment,
    records,
    dollars,
    record_share,
    dollar_share
from cms.clinician_payment_nature
order by dollars desc
```

<BarChart
  data={nature}
  x=nature_of_payment
  y=dollars
  swapXY=true
  title="2024 industry payments by nature of payment (dollars)"
  yFmt=usd1m
/>

<DataTable data={nature}>
  <Column id=nature_of_payment title="Nature of payment" wrap=true />
  <Column id=records title="Records" fmt=num0 />
  <Column id=record_share title="% of records" fmt=pct1 />
  <Column id=dollars title="Dollars" fmt=usd0 />
  <Column id=dollar_share title="% of dollars" fmt=pct1 />
</DataTable>

Read either column at a time: `Food and Beverage` is by far the most
common transfer type but each meal is small; `Royalty or License` is
the smallest transaction count on the chart (about 15k records) yet
tops the dollar ranking.

## Who pays

The top 15 payers by 2024 dollars. Roll-up is on
`paying_manufacturer_or_gpo_id`, so mixed-case duplicates of the
same entity collapse to one row and `any_value(name)` chooses a
single deterministic display label per id.

```sql payers
select
    payer_id,
    payer_name,
    records,
    clinicians_paid,
    dollars
from cms.clinician_top_payers
order by dollars desc
```

<BarChart
  data={payers}
  x=payer_name
  y=dollars
  swapXY=true
  title="Top 15 paying manufacturers / GPOs by 2024 dollars"
  yFmt=usd1m
/>

<DataTable data={payers}>
  <Column id=payer_name title="Payer" wrap=true />
  <Column id=records title="Records" fmt=num0 />
  <Column id=clinicians_paid title="Clinicians paid" fmt=num0 />
  <Column id=dollars title="Dollars" fmt=usd0 />
</DataTable>

The list splits by business model: pharma manufacturers (AbbVie,
Medtronic, Takeda, AstraZeneca) file hundreds of thousands of small
meal / consulting records against a broad clinician base, while a
few device and specialty firms (BioNTech, Edge Endo, DePuy Synthes)
concentrate nine-figure totals on a handful of clinicians. BioNTech's
number is almost entirely one royalty stream; Edge Endo's is a
single $91.08M acquisition payment to one endodontist.

## Who gets paid

Two rankings of the same specialty axis. First, top specialties by
total dollars — dominated by high-volume Internal Medicine plus
surgical fields with expensive implants. Endodontics ranks third
almost entirely on the strength of Edge Endo LLC's $91.1M
acquisition payment to a single clinician (see the per-clinician
note below):

```sql specialty_total
select
    specialty,
    clinicians,
    dollars,
    dollars_per_clinician
from cms.clinician_top_specialties
order by dollars desc
```

<BarChart
  data={specialty_total}
  x=specialty
  y=dollars
  swapXY=true
  title="Top 15 specialties by 2024 industry-payment dollars"
  yFmt=usd1m
/>

Second, the same table sorted by dollars per paid clinician (min
100 paid clinicians per specialty). The ranking flips: orthopaedic
sub-specialties, endodontics, and other implant-centric fields
average five figures per paid clinician, while primary-care
specialties average low three figures each even though the summed
total is large. Endodontics' top rank ($54K per clinician) is
carried almost entirely by 11 Edge Endo LLC records to 9
clinicians — one $91.08M acquisition line plus a handful of small
consulting and device-loan entries. Strip those 11 records out and
the per-clinician average falls ~89% to ~$5.9K, dropping
endodontics out of the top 15.

```sql specialty_per_clinician
select
    specialty,
    clinicians,
    dollars,
    dollars_per_clinician
from cms.clinician_top_specialties_per_clinician
order by dollars_per_clinician desc
```

<BarChart
  data={specialty_per_clinician}
  x=specialty
  y=dollars_per_clinician
  swapXY=true
  title="Top 15 specialties by 2024 $ per paid clinician (≥ 100 clinicians)"
  yFmt=usd0
/>

<DataTable data={specialty_per_clinician}>
  <Column id=specialty title="Specialty" wrap=true />
  <Column id=clinicians title="Clinicians" fmt=num0 />
  <Column id=dollars title="Total $" fmt=usd0 />
  <Column id=dollars_per_clinician title="$ / clinician" fmt=usd0 />
</DataTable>

## Payments and prescribing

The industry-payment fact and the Part D prescriber fact share NPI
as a key — the intersection is 642,414 clinicians who both received
industry payments in 2024 and appear in the prescriber-drug file.
The two facts describe different behaviors reported by different
parties, so the join surfaces an *association* between payment
receipt and prescribing volume. It does not measure whether
payments cause prescribing to change.

Grouping every prescriber by their total 2024 industry payments —
a "No payments" bucket for the 497k prescribers with none, then
deciles of the remaining 642k — median prescriber-billed drug cost
rises steeply across the paid deciles: from ~$2.7K in decile 1 to
~$162K in decile 9 (~59×), with decile 10 slightly below decile 9
at ~$148K:

```sql deciles
select
    bin,
    pay_bin,
    prescribers,
    avg_pay_dollars,
    median_pay_dollars,
    avg_rx_dollars,
    median_rx_dollars,
    avg_rx_claims
from cms.clinician_payment_vs_prescribing_deciles
order by pay_bin
```

<BarChart
  data={deciles}
  x=bin
  y=median_rx_dollars
  title="Median 2024 prescriber-billed drug cost by industry-payment decile"
  yFmt=usd0
/>

<DataTable data={deciles}>
  <Column id=bin title="Payment bin" />
  <Column id=prescribers title="Prescribers" fmt=num0 />
  <Column id=median_pay_dollars title="Median $ paid" fmt=usd0 />
  <Column id=median_rx_dollars title="Median $ prescribed" fmt=usd0 />
  <Column id=avg_rx_claims title="Avg claims" fmt=num0 />
</DataTable>

The association is real and large, but selection is heavy on both
sides: manufacturers target clinicians who already prescribe a lot,
and high-volume prescribers are more likely to be attend the meetings
and dinners where payments are filed. Median (not mean) is the
better summary here — decile 10's mean $ paid is inflated by a
handful of royalty recipients receiving seven and eight figures.

Sliced by specialty rather than by decile, the paid share is high
(≥ 70%) in nearly every high-volume prescribing specialty; primary
care and psychiatry are the outliers with paid shares closer to half.

```sql specialty_join
select
    prescriber_type,
    prescribers,
    paid_share,
    total_pay_dollars,
    total_rx_dollars,
    rx_cost_per_claim
from cms.clinician_payment_vs_prescribing_specialty
order by total_rx_dollars desc
```

<DataTable data={specialty_join}>
  <Column id=prescriber_type title="Specialty" wrap=true />
  <Column id=prescribers title="Prescribers" fmt=num0 />
  <Column id=paid_share title="% receiving any $" fmt=pct1 />
  <Column id=total_pay_dollars title="Total industry $" fmt=usd0 />
  <Column id=total_rx_dollars title="Total prescriber-billed $" fmt=usd0 />
  <Column id=rx_cost_per_claim title="$/claim" fmt=usd0 />
</DataTable>

### Do the drugs match?

The top 20 drug products by 2024 promotional spend, joined to Part D
prescriber-billed spend on the same brand (upper-cased brand-name
match against `fct_prescriber_drug_spending`). Rows with no Part D
match are honest nulls, not zeros — Comirnaty and Pluvicto aren't
Medicare Part D drugs, so their absence is the join working
correctly, not missing data.

```sql promoted
select
    product_name,
    promo_dollars,
    promoted_clinicians,
    part_d_rx_dollars,
    part_d_prescribers,
    part_d_claims
from cms.clinician_top_promoted_drugs
order by promo_dollars desc
```

<DataTable data={promoted}>
  <Column id=product_name title="Drug" />
  <Column id=promo_dollars title="2024 promo $" fmt=usd0 />
  <Column id=promoted_clinicians title="Promoted to" fmt=num0 />
  <Column id=part_d_rx_dollars title="Part D billed $" fmt=usd0 />
  <Column id=part_d_prescribers title="Part D prescribers" fmt=num0 />
</DataTable>

Ratio of promo $ to prescriber-billed $ varies by two orders of
magnitude across products — Jardiance sees ~$1 of promo per $700 of
prescribing, Sotyktu ~$1 per $4. Read this as a portfolio-strategy
signal (mature drugs get less promotion per prescribing dollar than
newly launched ones), not as an efficacy or influence signal.

## Utilization: paid vs unpaid

For the 1.24M individual-clinician rows in
`fct_physician_utilization` that also carry a payments-vs-no-payments
label, the median clinician who received any 2024 industry payment
bills roughly 1.8× the Medicare beneficiaries and 1.77× the Medicare
dollars of the median clinician who received none. Average HCC risk
score is essentially identical between the two cohorts — this isn't
about paid clinicians treating sicker patients.

```sql util
select
    cohort,
    clinicians,
    avg_beneficiaries,
    median_beneficiaries,
    avg_medicare_payment,
    median_medicare_payment,
    avg_hcc_risk,
    avg_pct_dual_eligible
from cms.clinician_utilization_paid_vs_unpaid
order by cohort desc
```

<DataTable data={util}>
  <Column id=cohort title="Cohort" />
  <Column id=clinicians title="Clinicians" fmt=num0 />
  <Column id=median_beneficiaries title="Median beneficiaries" fmt=num0 />
  <Column id=median_medicare_payment title="Median Medicare $" fmt=usd0 />
  <Column id=avg_hcc_risk title="Avg HCC risk" fmt=num2 />
  <Column id=avg_pct_dual_eligible title="Avg % dual-eligible" fmt=pct1 />
</DataTable>

Same caveat as the prescribing section: manufacturers target
high-volume clinicians, so the cohorts are not exchangeable. The
utilization gap is what the two selected populations look like side
by side, not the effect of receiving a payment.

## Caveats

- **One program year.** `fct_industry_payments` currently holds
  program year 2024 only (`payment_year = 2024`, published mid-2025).
  Nothing on this page is a time series; a paid clinician here means
  a clinician who received at least one reportable transfer during
  calendar 2024.
- **Coverage recipients are individuals + teaching hospitals.**
  51,278 records (~0.33%) carry no `covered_recipient_npi` and drop
  out of every NPI-based aggregation above: 37,388 name a teaching
  hospital rather than an individual clinician, and the remaining
  ~13.9K (7,729 non-physician practitioners + 6,161 physicians) are
  individual-clinician records filed without an NPI. All of these
  rows are still in the total dollar headline.
- **Roster coverage is partial.**
  <Value data={headline} column=dim_clinician_orphan_share fmt=pct1 /> of
  paid NPIs don't appear in `dim_clinician` — the roster covers only
  currently Medicare-enrolled clinicians while Sunshine reports on
  every US physician / dentist / APP a manufacturer paid, including
  retirees, out-of-network dentists, and clinicians who never billed
  Medicare. Charts that only need Open Payments fields (nature,
  payer, specialty, product) are unaffected; the utilization and
  prescribing joins silently drop those NPIs.
- **Prescribing snapshot has no year.**
  `fct_prescriber_drug_spending` is a single vintage of Part D
  prescriber-drug totals with no year column; the association charts
  compare 2024 industry payments to a snapshot of prescribing that
  covers calendar 2024 claims. Rows below 11 claims are suppressed by
  CMS and drop out of the join denominator.
- **Association ≠ causation.** Every payment-vs-prescribing or
  payment-vs-utilization comparison on this page is observational.
  Manufacturers target high-volume clinicians (payment goes toward
  where the demand is), so the cohorts on either side of any split
  are not exchangeable. Nothing here estimates the effect of
  receiving a payment on how much a clinician prescribes or bills.
- **`covered_recipient_specialty` uses NUCC pipe-delimited paths.**
  The "specialty" tables above show them verbatim rather than
  normalizing to a shorter label; that keeps the taxonomy honest
  (`Allopathic & Osteopathic Physicians|Orthopaedic Surgery` and
  `…|Orthopaedic Surgery|Orthopaedic Surgery of the Spine` are
  different specialties in the source) but forces a bit of scrolling.
- **Products are position-1 only.** Open Payments records can carry
  up to five associated products; `fct_industry_payments` exposes
  slot 1 (populated on ~94% of records) as `product_name` /
  `product_category`. The remaining slots stay in the staging layer.
