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

## What Medicare pays for

Switching from the payments-to-clinicians side to the payments-from-Medicare
side. `fct_hcpcs_service` rolls the CMS-published Physician & Other
Practitioners by-geography-and-service file up to
(`hcpcs_code`, `place_of_service`) — 13,463 National-grain rows in the
current 2026-05-21 vintage, one per procedure code × facility/office
split. Every headline below is computed from that National grain; state
rows never contribute to totals here.

```sql svc_headline
select
    service_rows,
    distinct_hcpcs,
    total_services,
    total_program_payment,
    median_payment_to_charge,
    drug_rows,
    as_of
from cms.physician_service_headline
```

<BigValue data={svc_headline} value=total_program_payment title="Total program payment (services × avg payment)" fmt=usd1b />
<BigValue data={svc_headline} value=total_services title="Total services billed" fmt=num0 />
<BigValue data={svc_headline} value=distinct_hcpcs title="Distinct HCPCS codes" fmt=num0 />
<BigValue data={svc_headline} value=median_payment_to_charge title="Median payment / charge ratio" fmt=pct1 />

3.55 billion services and $120.8B of Medicare program payment — the
"program payment" here is `sum(total_services * avg_medicare_payment_amount)`
across all 13,463 National rows, which is the CMS-published all-USA
dollar total for the fee-for-service physician side of Medicare
(carrier + DME) as reported in this file. Every dollar is exposed at
HCPCS grain, so a top-N ranking captures where the money actually
goes.

The top 20 (HCPCS, place) cells by total payment:

```sql top_payment
select
    hcpcs_code,
    hcpcs_description,
    place_of_service,
    hcpcs_drug_indicator,
    total_services,
    avg_medicare_payment_amount,
    total_program_payment,
    payment_to_charge_ratio
from cms.physician_service_top_payment
order by total_program_payment desc
```

<BarChart
  data={top_payment}
  x=hcpcs_code
  y=total_program_payment
  series=place_of_service
  swapXY=true
  title="Top 20 HCPCS × place-of-service cells by 2026-vintage program payment"
  yFmt=usd1b
/>

<DataTable data={top_payment}>
  <Column id=hcpcs_code title="HCPCS" />
  <Column id=hcpcs_description title="Description" wrap=true />
  <Column id=place_of_service title="Place" />
  <Column id=total_services title="Services" fmt=num0 />
  <Column id=avg_medicare_payment_amount title="$ / service" fmt=usd2 />
  <Column id=total_program_payment title="Total $" fmt=usd0 />
  <Column id=payment_to_charge_ratio title="Pay / charge" fmt=pct1 />
</DataTable>

Two shapes dominate the list. Office E&M (99214, 99213, 99215, 99204,
G0439 wellness visits) rings up billions on very high volume — 99214
alone is $8.0B across 95M services. Facility inpatient E&M (99223,
99232, 99233, 99285 ED visits, 99291 critical care) is the same story
on the hospital side. Punctuating both tails are a handful of
per-unit-expensive items: cataract removal (66984), Part-B drugs
(J0178 aflibercept, J9271 pembrolizumab, J2777 faricimab), and a few
graft/wrap codes (Q4205, Q4271) where the average charge runs into
four figures.

### Facility vs office

```sql place_split
select
    place,
    service_rows,
    distinct_hcpcs,
    total_services,
    total_program_payment,
    avg_payment_per_service
from cms.physician_service_place_split
```

<DataTable data={place_split}>
  <Column id=place title="Place of service" />
  <Column id=service_rows title="Rows" fmt=num0 />
  <Column id=distinct_hcpcs title="Distinct HCPCS" fmt=num0 />
  <Column id=total_services title="Services" fmt=num0 />
  <Column id=total_program_payment title="Total $" fmt=usd0 />
  <Column id=avg_payment_per_service title="$ / service" fmt=usd2 />
</DataTable>

Office / non-facility accounts for the bulk of both service volume
(3.05B of 3.55B, 86%) and dollars ($85.6B of $120.8B, 71%). Facility
services are fewer (506M) but each one costs Medicare more on average
($69.52 vs $28.09) — the site-of-service differential is worth about
2.5× per service in this vintage.

## Payment vs charge

Providers submit charges (`avg_submitted_charge`) that are far higher
than what Medicare's fee schedule actually pays. The median HCPCS ×
place cell has a `payment_to_charge_ratio` of
<Value data={svc_headline} column=median_payment_to_charge fmt=pct1 />
— Medicare pays about 17 cents per submitted dollar on the typical
service.

Bucketed distribution across all 13,463 National-grain rows:

```sql pay_charge_buckets
select
    bucket,
    service_rows,
    total_services,
    program_payment
from cms.physician_service_payment_charge_buckets
```

<BarChart
  data={pay_charge_buckets}
  x=bucket
  y=service_rows
  title="HCPCS × place cells by payment-to-charge ratio"
  yFmt=num0
/>

<DataTable data={pay_charge_buckets}>
  <Column id=bucket title="Pay / charge bucket" />
  <Column id=service_rows title="HCPCS rows" fmt=num0 />
  <Column id=total_services title="Services" fmt=num0 />
  <Column id=program_payment title="Program $" fmt=usd0 />
</DataTable>

Just under half the rows (6,579 of 13,463, 49%) land in the 10–20%
band, and a further 2,783 (21%) in 20–30%. Only 588 rows (4.4%) pay
back more than half of the submitted charge, and 181 (1.3%) pay 75%
or more — mostly low-dollar items where the submitted charge is
already close to the fee schedule.

Absolute-dollar gaps concentrate in the highest-volume services. The
15 HCPCS with the largest total `submitted − paid` gap (at least
100k services nationally):

```sql charge_gap
select
    hcpcs_code,
    hcpcs_description,
    place_of_service,
    total_services,
    avg_submitted_charge,
    avg_medicare_payment_amount,
    payment_to_charge_ratio,
    charge_minus_payment_dollars
from cms.physician_service_charge_gap
order by charge_minus_payment_dollars desc
```

<BarChart
  data={charge_gap}
  x=hcpcs_code
  y=charge_minus_payment_dollars
  swapXY=true
  title="Top 15 HCPCS by total submitted-minus-paid gap (services ≥ 100k)"
  yFmt=usd1b
/>

<DataTable data={charge_gap}>
  <Column id=hcpcs_code title="HCPCS" />
  <Column id=hcpcs_description title="Description" wrap=true />
  <Column id=place_of_service title="Place" />
  <Column id=avg_submitted_charge title="Avg charge" fmt=usd2 />
  <Column id=avg_medicare_payment_amount title="Avg paid" fmt=usd2 />
  <Column id=payment_to_charge_ratio title="Pay / charge" fmt=pct1 />
  <Column id=charge_minus_payment_dollars title="Total gap" fmt=usd0 />
</DataTable>

The largest single gap is 99214 at $18.4B — 95M services with an
average charge of $276 against a paid amount of $83.75. ED visits
(99285), knee replacement (27447), and critical-care (99291) all pay
back 10–20% of the submitted charge. Read this as reporting
convention rather than as denial: `avg_submitted_charge` is what the
provider population billed, which under Medicare is largely irrelevant
because the program pays the fee schedule regardless of what the
claim says. The submitted charge is a data-quality signal about the
provider's non-Medicare billing baseline, not a negotiation
counter-offer.

## Geography benchmarks

`fct_physician_service_geography` carries a National benchmark inline
on every state row (`national_avg_medicare_payment_amount` and
friends), which makes state-vs-national comparisons a single-table
lookup. Aggregating a state's own service mix at state prices versus
the same mix at national prices gives a "payment index" — greater
than 1 means the state gets paid above what the national fee
schedule would apply to its mix, less than 1 means below. All the
state rankings here are the 50 states + DC only; the territory codes
(60/66/69/72/78) and Armed Forces / unknown / foreign pseudo-codes
(9A–9E) are excluded because their volumes are small enough that a
handful of outlier cells swing the aggregate, and the five state
rows CMS emitted with NULL geography_code (see caveats) are dropped
as well.

```sql state_index
select
    geography_code,
    geography_description,
    state_services,
    state_payment,
    payment_index
from cms.physician_service_state_index
order by payment_index desc
```

<BarChart
  data={state_index}
  x=geography_description
  y=payment_index
  swapXY=true
  title="State payment index — state mix priced at state vs national avg"
  yFmt=num2
>
  <ReferenceLine y=1 label="National = 1.00" />
</BarChart>

<DataTable data={state_index}>
  <Column id=geography_description title="State" />
  <Column id=state_services title="Services" fmt=num0 />
  <Column id=state_payment title="State $" fmt=usd0 />
  <Column id=payment_index title="Payment index" fmt=num3 />
</DataTable>

Alaska tops the ranking at 1.162, then a cluster of high-cost / high
GPCI states (NY 1.083, DC 1.076, NJ 1.071, CA 1.069). Maine anchors
the bottom at 0.875, alongside Alabama, West Virginia, South Dakota,
and Kentucky (all ≤ 0.92). The median state runs at 0.969 — most
states get slightly less per unit of service than the national
average, which is exactly what happens when the population-weighted
national average is pulled up by a small number of large
high-cost-of-labor states.

Zooming in on a single anchor code — 99214 O, the highest-payment
single cell in the file at $8.0B nationally — the same pattern shows
up cleanly:

```sql anchor
select
    geography_code,
    geography_description,
    total_services,
    state_avg_payment,
    national_avg_payment,
    share_of_national_services,
    payment_ratio
from cms.physician_service_state_anchor_99214
order by payment_ratio desc
```

<ScatterPlot
  data={anchor}
  x=share_of_national_services
  y=payment_ratio
  title="99214 O — state vs national payment ratio by share of national volume"
  xAxisTitle="Share of national 99214 services"
  yAxisTitle="State $/service ÷ national $/service"
  xFmt=pct2
  yFmt=num2
  pointSize=8
>
  <ReferenceLine y=1 label="National = 1.00" />
</ScatterPlot>

Alaska pays 1.211× the national average ($101.38 vs $83.75), DC
1.158, New York 1.156, California 1.129, New Jersey 1.125. At the
other end North Dakota, Maine, and Arkansas run at 0.81–0.85. The
spread — top state pays about 1.50× what the bottom state does — is
entirely fee-schedule geography (GPCI locality adjustments). It is
not a quality or intensity signal.

## Caveats

- **Service-file snapshot has no year.** `fct_hcpcs_service` and
  `fct_physician_service_geography` are single-vintage rollups of the
  Physician & Other Practitioners by-geography-and-service file
  (2026-05-21 in the current vintage, `as_of` column). CMS does not
  publish a claims year on this file, so nothing in the service and
  geography sections is a time series.
- **National-grain is authoritative for totals.**
  `fct_hcpcs_service` sources its 13,463 rows from the National rows
  of the upstream staging model rather than aggregating the 9.78M-row
  by-provider-and-service file. The two disagree because CMS drops
  (npi, hcpcs, pos) cells with 10 or fewer beneficiaries from the
  provider file — 22.4% of program-wide services (798M of 3.55B)
  live entirely in that sub-11 suppression tail. Summing state rows
  in `fct_physician_service_geography` also under-counts national
  volume for the same reason. Every total on this page is computed
  from the National grain.
- **`avg_submitted_charge` is not a negotiation.** Under Medicare
  fee-for-service, the program pays the fee schedule regardless of
  what the claim's submitted amount says. The submitted charge in
  this file is a provider-population average — a data-quality
  reflection of what the provider bills their non-Medicare book —
  not evidence of a rejected offer. All the payment-vs-charge charts
  above should be read as descriptive, not as denial rates.
- **Geography rankings exclude territories and NULL-code rows.** The
  50-states-plus-DC filter drops five state rows CMS emitted without
  a geography_code (all E&M / psychotherapy codes: 90833/F, 99223/F,
  99232/F, 99233/F, 99239/F), the five territory codes 60 (AS), 66
  (GU), 69 (MP), 72 (PR), 78 (VI), and the five pseudo-codes 9A
  (Armed Forces Central/South America) through 9E (Foreign Country).
  All 10 non-state codes are populated as ordinary state rows in the
  mart — this is a display choice for the rankings only.
- **State `payment_to_charge_ratio` can exceed 1.0.** 13 state rows
  in the current vintage cross the 1.0 line — 12 for HCPCS M0010
  (chelation therapy, ~$70 baseline) and one for G0442. National
  rows never do. Geographic-adjustment multipliers occasionally push
  a small-dollar service above the provider-population average
  submitted charge; those rows are legitimate and are included as-is.

## Open-Payments caveats

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
