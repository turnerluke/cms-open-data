---
title: Medicaid drug utilization
---

Medicaid State Drug Utilization Data (SDUD) for calendar 2023 — the
outpatient drug claims that state Medicaid programs report to CMS to
support manufacturer rebates. Everything on this page comes from two
marts: `fct_medicaid_drug_state` at the (state, NDC, year) grain, and
`fct_medicaid_medicare_drug_spend` for the program-level comparison
against Medicare Part D and Part B. All figures are 2023.

```sql headline
select
    total_amount_reimbursed,
    medicaid_amount_reimbursed,
    non_medicaid_amount_reimbursed,
    ffs_medicaid_amount_reimbursed,
    mco_medicaid_amount_reimbursed,
    mco_share_of_medicaid,
    mco_share_of_total,
    number_of_prescriptions,
    distinct_ndcs,
    distinct_labelers,
    as_of
from cms.medicaid_headline
```

<BigValue data={headline} value=total_amount_reimbursed title="Medicaid drug reimbursement" fmt=usd1b />
<BigValue data={headline} value=medicaid_amount_reimbursed title="Medicaid payer share" fmt=usd1b />
<BigValue data={headline} value=number_of_prescriptions title="Prescriptions" fmt=num0 />
<BigValue data={headline} value=distinct_ndcs title="Distinct NDCs" fmt=num0 />
<BigValue data={headline} value=mco_share_of_medicaid title="MCO share of Medicaid dollars" fmt=pct1 />

Medicaid outpatient drug reimbursement (payer + third-party) totalled
<Value data={headline} value=total_amount_reimbursed fmt=usd1b /> in 2023
across <Value data={headline} value=number_of_prescriptions fmt=num0 />
prescriptions and <Value data={headline} value=distinct_ndcs fmt=num0 />
distinct NDCs, dispensed by
<Value data={headline} value=distinct_labelers fmt=num0 /> labelers
(manufacturers / repackagers). The Medicaid programs' own share of that
was <Value data={headline} value=medicaid_amount_reimbursed fmt=usd1b />
(the balance is the "non-Medicaid" third-party co-payer share reported
alongside every claim). All headline values are read from the CMS
unsuppressed national aggregate rows (`state = 'XX'`), not from a sum
across the states — see the caveats below.

## FFS vs MCO: the managed-care shift

Every SDUD row is tagged as either **fee-for-service** — the state
Medicaid agency paying pharmacies directly — or **managed-care** — a
capitated MCO paying pharmacies as part of its benefit. Nationally the
MCO channel now clears more dollars than FFS:

```sql channel_split
select
    program_name,
    total_spending,
    total_claims,
    spending_per_claim
from cms.medicaid_channel_split
```

<BarChart
  data={channel_split}
  x=program_name
  y=total_spending
  title="National Medicaid drug reimbursement by channel"
  yFmt=usd1b
/>

<DataTable data={channel_split}>
  <Column id=program_name title="Channel" />
  <Column id=total_spending title="Reimbursement" fmt=usd0 />
  <Column id=total_claims title="Prescriptions" fmt=num0 />
  <Column id=spending_per_claim title="$/rx" fmt=usd2 />
</DataTable>

The mix is uneven state by state. A handful of states run essentially
FFS-only pharmacy programs (a "pharmacy carve-out" from the MCO
contract), and about a third run essentially MCO-only:

```sql mco_summary
select
    states,
    carve_out_states,
    mco_dominant_states,
    median_mco_share,
    min_mco_share,
    max_mco_share
from cms.medicaid_state_mco_summary
```

Of the <Value data={mco_summary} value=states /> reporting states
(50 + DC + PR), <Value data={mco_summary} value=carve_out_states /> land
below 10% MCO share (Vermont, West Virginia, Colorado, California,
North Dakota, and Tennessee all keep pharmacy on the FFS side) and
<Value data={mco_summary} value=mco_dominant_states /> land above 90%
MCO (Puerto Rico, Nebraska, Hawaii, Kansas, Virginia, Delaware,
New Jersey, Iowa, Pennsylvania, Texas, and others). California — the
single largest Medicaid drug program at over $13B in state-tier
reimbursement — is a carve-out at under 5% MCO in 2023, an outsized
influence on the national ordering.

```sql state_mco_share
select
    state,
    ffs_medicaid,
    mco_medicaid,
    medicaid_total,
    mco_share,
    prescriptions
from cms.medicaid_state_mco_share
```

<BarChart
  data={state_mco_share}
  x=state
  y=mco_share
  title="Managed-care share of Medicaid drug reimbursement by state"
  yFmt=pct0
/>

## Where the money goes

The top-15 NDCs nationally by Medicaid reimbursement — anti-TNF and
anti-integrin biologics (Humira, Stelara), HIV combination therapy
(Biktarvy), cystic-fibrosis triple therapy (Trikafta), GLP-1 agonists
(Trulicity, Ozempic), a DOAC (Eliquis), atypical antipsychotic depot
(Invega Sustenna), insulin (Lantus), SGLT2 inhibitors (Jardiance),
and MAT (Suboxone). The `product_name` column CMS ships is **truncated
at 10 characters** and one NDC can carry several truncated strings, so
this table aggregates by NDC and only *displays* one representative
name — never join Medicaid rows on the truncated name.

```sql top_drugs
select
    ndc,
    product_name,
    labeler_code,
    number_of_prescriptions,
    medicaid_amount_reimbursed,
    ffs_medicaid_amount_reimbursed,
    mco_medicaid_amount_reimbursed,
    mco_share_of_medicaid_amount,
    medicaid_per_rx
from cms.medicaid_top_drugs
```

<BarChart
  data={top_drugs}
  x=product_name
  y=medicaid_amount_reimbursed
  swapXY=true
  title="Top 15 NDCs by Medicaid reimbursement (national, 2023)"
  yFmt=usd1b
/>

<DataTable data={top_drugs}>
  <Column id=product_name title="Product (truncated)" />
  <Column id=ndc title="NDC" />
  <Column id=labeler_code title="Labeler" />
  <Column id=number_of_prescriptions title="Prescriptions" fmt=num0 />
  <Column id=medicaid_amount_reimbursed title="Medicaid $" fmt=usd0 />
  <Column id=medicaid_per_rx title="Medicaid $/rx" fmt=usd0 />
  <Column id=mco_share_of_medicaid_amount title="MCO share" fmt=pct0 />
</DataTable>

Rolled up by labeler code (the five-digit NDC prefix that identifies
the manufacturer or repackager), a small number of firms carry the
bulk of Medicaid drug spending — the top labeler alone (AbbVie,
labeler `00074`) clears $7.6B of Medicaid dollars across the 152
NDCs with disclosed Medicaid reimbursement.

```sql top_labelers
select
    labeler_code,
    ndcs,
    prescriptions,
    medicaid_spend,
    total_spend
from cms.medicaid_top_labelers
```

<BarChart
  data={top_labelers}
  x=labeler_code
  y=medicaid_spend
  swapXY=true
  title="Top 15 labelers by Medicaid reimbursement (national, 2023)"
  yFmt=usd1b
/>

## Medicaid vs Medicare in one chart

Setting Medicaid alongside Medicare Part D (retail pharmacy) and
Part B (physician-administered) puts the programs' relative scale in
context. Part D is more than twice Medicaid and dwarfs Part B; Part B
lands roughly between Medicaid FFS and MCO on its own:

```sql program_compare
select
    program_name,
    payer,
    total_spending,
    total_claims
from cms.medicaid_medicare_compare
where program_name in (
    'Medicaid FFS', 'Medicaid MCO', 'Medicare Part B', 'Medicare Part D'
)
```

<BarChart
  data={program_compare}
  x=program_name
  y=total_spending
  series=payer
  title="Drug spending by federal program, 2023"
  yFmt=usd1b
/>

The Part D figure here — $275.8B — is the CMS *drug-spending-by-drug*
file's manufacturer roll-up total. It intentionally differs from the
$288.4B Part D total shown on the [/prescribers](/prescribers) page,
which comes from the CMS prescriber-profile file; the two sources roll
up different universes (drug-level vs per-NPI) and neither reconciles
to the other. The two totals are never compared inside a single chart
on this site.

Because SDUD keys drugs by NDC while the Medicare files key by
brand / generic name and carry no NDC, this comparison intentionally
stops at the program aggregate. A prefix-10 name join against
`dim_drug` matches only about a third of Medicaid dollars unambiguously
and misses more than half entirely — see the `fct_medicaid_medicare_
drug_spend` mart docs for the measured match rates.

## State-level Medicaid spending

Aggregate state spending tracks Medicaid enrollment (which SDUD does
not publish), so a per-capita ranking is not available from this
source. Ranking on raw dollars puts California and New York on top
by a wide margin, with Virginia — nearly all of it MCO — a distant
third:

```sql state_spending
select
    state,
    ffs_medicaid,
    mco_medicaid,
    medicaid_total,
    prescriptions,
    medicaid_per_rx
from cms.medicaid_state_spending
```

<BarChart
  data={state_spending}
  x=state
  y=medicaid_total
  title="Top 15 states by Medicaid drug reimbursement (state tier, 2023)"
  yFmt=usd1b
/>

<DataTable data={state_spending}>
  <Column id=state title="State" />
  <Column id=ffs_medicaid title="FFS Medicaid $" fmt=usd0 />
  <Column id=mco_medicaid title="MCO Medicaid $" fmt=usd0 />
  <Column id=medicaid_total title="Combined Medicaid $" fmt=usd0 />
  <Column id=prescriptions title="Prescriptions" fmt=num0 />
  <Column id=medicaid_per_rx title="$/rx" fmt=usd2 />
</DataTable>

```sql undercount
select
    national_total,
    national_medicaid,
    state_tier_total,
    state_tier_medicaid,
    suppression_gap_total,
    suppression_gap_medicaid,
    suppression_gap_share,
    states,
    state_rows,
    fully_suppressed_rows,
    fully_suppressed_share
from cms.medicaid_state_undercount
```

The state totals in the table above are known to **undercount** by
about <Value data={undercount} value=suppression_gap_share fmt=pct1 />.
CMS blanks the five measure columns on any (state × NDC × quarter)
row with 1–10 prescriptions, so summing the 52 disclosed state rows
lands at <Value data={undercount} value=state_tier_total fmt=usd1b />
against <Value data={undercount} value=national_total fmt=usd1b /> in
the CMS-computed national aggregate — a gap of
<Value data={undercount} value=suppression_gap_total fmt=usd1b />
that lives inside the small state × NDC cells. The gap is not
uniformly distributed: a per-state ranking is directionally right
but not exact for the smaller states.
<Value data={undercount} value=fully_suppressed_share fmt=pct0 />
of state-tier (state × NDC) rows have every measure suppressed and
contribute nothing to any state total.

## Caveats

- **Never mix `'XX'` with state rows.** CMS publishes both a national
  aggregate (`state = 'XX'`, 53,205 rows in the mart) that re-adds
  small-cell values and a disclosed state tier (52 codes,
  1,201,587 rows) that does not. The mart's `is_state_tier` flag
  keeps the two apart; every roll-up on this page filters to exactly
  one tier and the state-level sections quote the suppression gap
  explicitly.
- **`product_name` is truncated at 10 characters** and 32,704 of the
  53,205 NDCs (61%) carry more than one truncated string across the
  file's state rows (within the national tier each NDC carries a
  single name). The name column is displayed for readability but
  every aggregation on this page groups by NDC or labeler code, never
  by the truncated name.
- **No reliable NDC ↔ brand/generic crosswalk to `dim_drug`.**
  Prefix-10 name matching covers only ~33% of Medicaid dollars
  unambiguously, so cross-program drug-level comparisons against
  Part D or Part B are intentionally not attempted. Program-level
  aggregates (the bar chart above) are the strongest comparison this
  page will make.
- **Part D total shown here ≠ Part D total on /prescribers.**
  $275.8B (spending-by-drug file) vs $288.4B (prescriber-profile
  file). Two different CMS source files with different universes;
  they don't reconcile and this site does not mix them within a
  single chart.
- **`units_reimbursed` is package-units.** The unit depends on each
  NDC's packaging (bottles, boxes, vials), so it's summable within an
  NDC but not across NDCs — that's why this page reports
  prescriptions, never units.
- **Single vintage.** SDUD 2023 is the only year in the current
  registry; nothing on this page is a time series. The mart's `as_of`
  column carries the upstream `modified` date
  (<Value data={headline} value=as_of fmt=id />).
- **Reimbursement ≠ net Medicaid drug cost.** SDUD dollars are gross
  pharmacy reimbursement (payer + third-party); the manufacturer
  rebates that Medicaid negotiates against these files reduce the net
  materially and are not published at the NDC level.
