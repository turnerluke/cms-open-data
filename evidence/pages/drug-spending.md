---
title: Drug spending
---

Medicare drug spending from two programs: **Part D** (pharmacy-dispensed
prescriptions, reported per drug and manufacturer) and **Part B**
(physician-administered drugs, reported per HCPCS billing code). Part D
figures below use CMS's `'Overall'` manufacturer roll-up rows only, so
no drug is double-counted across its manufacturers.

```sql latest_year
select least(
    (select max(spending_year) from cms.part_d_drug_spending),
    (select max(spending_year) from cms.part_b_drug_spending)
) as latest_year
```

## Top drugs by total spending (<Value data={latest_year} column=latest_year fmt=id />)

All single-year figures below use the latest year available in **both**
programs, so Part B and Part D are always compared like-for-like even
if one file gains a new year first.

```sql top_part_d
select
    brand_name,
    generic_name,
    total_spending,
    total_claims,
    total_beneficiaries,
    spending_per_beneficiary_derived
from cms.part_d_drug_spending
where
    is_manufacturer_rollup
    and spending_year = least(
        (select max(spending_year) from cms.part_d_drug_spending),
        (select max(spending_year) from cms.part_b_drug_spending)
    )
order by total_spending desc
limit 10
```

```sql top_part_b
select
    coalesce(brand_name, generic_name, hcpcs_code) as drug_name,
    hcpcs_code,
    total_spending,
    total_claims,
    total_beneficiaries,
    spending_per_beneficiary_derived
from cms.part_b_drug_spending
where spending_year = least(
    (select max(spending_year) from cms.part_d_drug_spending),
    (select max(spending_year) from cms.part_b_drug_spending)
)
order by total_spending desc
limit 10
```

<BarChart
  data={top_part_d}
  x=brand_name
  y=total_spending
  swapXY=true
  title="Part D — top 10 drugs"
  yFmt=usd1b
/>

<BarChart
  data={top_part_b}
  x=drug_name
  y=total_spending
  swapXY=true
  title="Part B — top 10 drugs"
  yFmt=usd1b
/>

## Spending trend by program

```sql program_trend
select
    spending_year,
    'Part D' as program,
    sum(total_spending) as total_spending
from cms.part_d_drug_spending
where is_manufacturer_rollup
group by 1
union all
select
    spending_year,
    'Part B',
    sum(total_spending)
from cms.part_b_drug_spending
group by 1
order by spending_year
```

<LineChart
  data={program_trend}
  x=spending_year
  y=total_spending
  series=program
  title="Total drug spending by year"
  yFmt=usd1b
/>

## Drugs billed in both programs

Joined through `dim_drug`, which conforms Part B and Part D on exact
(upper-cased) brand + generic name matches — treat the overlap as a
lower bound, since name formatting differs between the two files.

```sql part_b_vs_part_d
with part_d as (
    select
        drug_key,
        sum(total_spending) as part_d_spending
    from cms.part_d_drug_spending
    where
        is_manufacturer_rollup
        and spending_year = least(
            (select max(spending_year) from cms.part_d_drug_spending),
            (select max(spending_year) from cms.part_b_drug_spending)
        )
    group by 1
),

part_b as (
    select
        drug_key,
        sum(total_spending) as part_b_spending
    from cms.part_b_drug_spending
    where
        drug_key is not null
        and spending_year = least(
            (select max(spending_year) from cms.part_d_drug_spending),
            (select max(spending_year) from cms.part_b_drug_spending)
        )
    group by 1
)

select
    d.brand_name,
    d.generic_name,
    part_d.part_d_spending,
    part_b.part_b_spending,
    part_d.part_d_spending + part_b.part_b_spending as combined_spending
from cms.dim_drug as d
inner join part_d using (drug_key)
inner join part_b using (drug_key)
where d.in_part_b and d.in_part_d
order by combined_spending desc
limit 15
```

<DataTable data={part_b_vs_part_d}>
  <Column id=brand_name title="Brand" />
  <Column id=generic_name title="Generic" />
  <Column id=part_d_spending title="Part D" fmt=usd0 />
  <Column id=part_b_spending title="Part B" fmt=usd0 />
  <Column id=combined_spending title="Combined" fmt=usd0 />
</DataTable>

## Caveats

- **Part D total shown here ≠ Part D total on /prescribers.** This
  page's Part D figures come from the CMS *spending-by-drug* file
  (2023 program-wide roll-up: $275.8B, `'Overall'` manufacturer rows
  in `fct_part_d_drug_spending`). The
  [/prescribers](/prescribers) page reports Part D from the CMS
  *prescriber-profile* file ($288.4B total drug cost; $284.8B
  MAPD+PDP in `fct_prescriber_profile`). The two CMS sources roll
  up different universes — drug-level spending vs per-NPI prescriber
  totals — and neither reconciles to the other; the site convention
  is to stay within one source per page.
- **`'Overall'` manufacturer rows are kept for drug-level analysis.**
  Part D's spending file publishes both per-manufacturer rows and an
  `'Overall'` roll-up for each drug. `fct_part_d_drug_spending`
  keeps both and flags the roll-up via `is_manufacturer_rollup`. Every
  Part D chart on this page filters on that flag; summing
  `total_spending` without it double-counts.
- **Part B has no manufacturer breakdown.** CMS publishes Part B
  spending per HCPCS billing code only, so a single code can cover
  several branded drugs — the `brand_name` column occasionally lists
  multiple values. Summing Part B `total_spending` needs no roll-up
  filter.
- **Unmarketed drug-years are dropped, suppressed cells are kept.**
  Both facts drop rows where every metric for a drug-year is null
  (the drug wasn't marketed that year — 11,038 rows dropped in Part
  D). Individual cells that CMS suppressed for privacy stay `NULL`
  and are never coalesced to 0, so per-beneficiary and
  per-claim-derived metrics disappear on small cells rather than
  reading as $0.
- **`dim_drug` join is name-based.** The Part B ↔ Part D overlap
  table joins on `drug_key`, a hash of upper-cased brand + generic
  names. Name formatting differs between the two files, so treat
  the overlap as a lower bound on drugs billed in both programs.
  Part B rows whose HCPCS code carries no drug name (e.g.
  not-otherwise-classified codes) have `drug_key = NULL` and are
  excluded from the join.
