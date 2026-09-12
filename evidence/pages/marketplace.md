---
title: Marketplace (Qualified Health Plans)
---

Individual and small-group (SHOP) qualified health plans available on
the Federally-Facilitated Marketplace for plan year 2026, published by
CMS in the PY2026 QHP Landscape files. `dim_qhp_plan` holds one row per
plan; `fct_qhp_premiums` unrolls the CMS rating template into
plan × county × household-scenario premium quotes; `fct_qhp_cost_sharing`
holds the deductible / MOOP grid alongside each plan's silver
cost-sharing-reduction (CSR) variants. All page views read a
pre-aggregated source query — the ~5.4 M premium rows never leave the
warehouse.

```sql headline
select
    plans,
    individual_medical_plans,
    individual_dental_plans,
    shop_plans,
    issuers,
    individual_medical_issuers,
    states,
    counties,
    premium_rows,
    cost_sharing_rows,
    plan_as_of,
    plan_year
from cms.qhp_stats
```

<BigValue data={headline} value=individual_medical_plans title="Individual medical plans" fmt=num0 />
<BigValue data={headline} value=individual_medical_issuers title="Issuers (individual medical)" fmt=num0 />
<BigValue data={headline} value=states title="FFM states covered" fmt=num0 />
<BigValue data={headline} value=plan_year title="Plan year" fmt=id />

## Framing caveat: FFM only, not national

This page covers **only the <Value data={headline} column=states fmt=num0 />
states that use HealthCare.gov** — the Federally-Facilitated Marketplace
plus the state-partnership marketplaces. State-based exchanges
(including California, Colorado, Connecticut, DC, Georgia, Idaho,
Illinois, Kentucky, Maine, Maryland, Massachusetts, Minnesota, Nevada,
New Jersey, New Mexico, New York, Pennsylvania, Rhode Island, Vermont,
Virginia, and Washington)
run their own plan-shopping platforms and are absent from the CMS
landscape files. Any state-level statistic below is a partial
picture of the U.S. individual market.

The SHOP (small-group) landscape in this vintage is nearly empty —
<Value data={headline} column=shop_plans fmt=num0 /> plans in
four states (AL, MT, NH, WI on the medical side; WI-only on dental).
Every analysis below restricts to the individual market unless noted.

## Benchmark silver premiums by state

The **lowest-cost silver plan** in each county is the anchor for
premium-tax-credit calculations under the ACA — enrollee subsidies
grow so that a household pays at most a fixed share of income for that
plan. The chart below averages that lowest-silver monthly premium
across counties in each state for a 40-year-old buying an individual
policy.

```sql silver_state
select
    state_code,
    counties,
    avg_lowest_silver_premium,
    median_lowest_silver_premium,
    min_silver_premium,
    max_silver_premium
from cms.qhp_silver_by_state
order by avg_lowest_silver_premium
```

<BarChart
  data={silver_state}
  x=state_code
  y=avg_lowest_silver_premium
  title="Average lowest-cost silver monthly premium — age 40, individual"
  yFmt=usd0
  sort=false
/>

The spread is wide even inside the FFM footprint: New Hampshire's
average lowest-cost silver runs about $400/month; Wyoming's is nearly
triple that. Alaska, Wyoming, and West Virginia are the three
consistently most-expensive FFM states across all metal tiers.

<DataTable data={silver_state} rows=15>
  <Column id=state_code title="State" />
  <Column id=counties title="Counties" fmt=num0 />
  <Column id=avg_lowest_silver_premium title="Avg lowest silver" fmt=usd0 />
  <Column id=median_lowest_silver_premium title="Median lowest silver" fmt=usd0 />
  <Column id=min_silver_premium title="Min county" fmt=usd0 />
  <Column id=max_silver_premium title="Max county" fmt=usd0 />
</DataTable>

### County-level spread

Each point is one county's lowest-cost silver premium (age 40,
individual). Within-state variation is the geographic-rating-area
signal — Texas alone spans more than $400 between its cheapest and
most-expensive lowest-silver counties.

```sql silver_counties
select
    state_code,
    fips_county_code,
    county_name,
    min_silver_premium
from cms.qhp_silver_county_spread
```

<ScatterPlot
  data={silver_counties}
  x=state_code
  y=min_silver_premium
  series=state_code
  title="Lowest-cost silver premium by county"
  yFmt=usd0
  yAxisTitle="Monthly premium, age 40"
  pointSize=3
  legend=false
/>

## Premium spread by metal level

Metal levels reflect actuarial value: Bronze / Expanded Bronze plans
cover ~60% of expected medical costs, Silver ~70%, Gold ~80%,
Platinum ~90%. Catastrophic plans are limited to enrollees under 30
or with a hardship exemption and carry the lowest premiums but no
premium-tax-credit eligibility. The IQR bars below show 25th–75th
percentile monthly premium at age 40 across every county-plan
offering in the FFM.

```sql metal_premiums
select
    metal_level,
    plans,
    plan_county_offerings,
    p25_premium,
    median_premium,
    p75_premium,
    p10_premium,
    p90_premium,
    avg_premium,
    metal_sort
from cms.qhp_metal_premiums
order by metal_sort
```

<BarChart
  data={metal_premiums}
  x=metal_level
  y=median_premium
  title="Median monthly premium at age 40 by metal level"
  yFmt=usd0
  sort=false
/>

<DataTable data={metal_premiums}>
  <Column id=metal_level title="Metal" />
  <Column id=plans title="Plans" fmt=num0 />
  <Column id=plan_county_offerings title="Plan-county offerings" fmt=num0 />
  <Column id=p25_premium title="25th %ile" fmt=usd0 />
  <Column id=median_premium title="Median" fmt=usd0 />
  <Column id=p75_premium title="75th %ile" fmt=usd0 />
  <Column id=avg_premium title="Mean" fmt=usd0 />
</DataTable>

The Gold–Silver gap is small in this vintage — the median gold plan
runs only about 4% above the median silver ($774 vs $745) — a pattern
that reflects
"silver loading" (the practice of concentrating the cost of the
unfunded CSR benefit into silver premiums). Expanded Bronze plans,
which allow one additional service before the deductible, sit noticeably
above plain Bronze.

## Issuer concentration

Herfindahl-Hirschman Index (HHI) computed over each issuer's share of
individual-medical plan-county offerings in the state (age-40 individual
scenario used as the enumeration basis so every plan counts once per
county in which it is sold). HHI values are on the standard 0–10,000
scale where the U.S. Department of Justice guidelines call anything
above 2,500 "highly concentrated" and above 1,800 "moderately
concentrated." Note this is a plan-availability HHI, not an
enrollment-share HHI — CMS does not publish plan-level enrollment
counts in the landscape file.

```sql issuer_hhi
select
    state_code,
    issuers,
    hhi,
    top_issuer_share
from cms.qhp_issuer_concentration
order by hhi desc
```

<BarChart
  data={issuer_hhi}
  x=state_code
  y=hhi
  title="Issuer concentration (HHI, plan-county offerings basis)"
  yFmt=num0
  sort=false
/>

<DataTable data={issuer_hhi} rows=15>
  <Column id=state_code title="State" />
  <Column id=issuers title="Issuers" fmt=num0 />
  <Column id=hhi title="HHI" fmt=num0 />
  <Column id=top_issuer_share title="Top issuer share" fmt=pct1 />
</DataTable>

Every FFM state is at least "moderately concentrated." Alaska, West
Virginia, Hawaii, and Wyoming operate with just two individual-medical
issuers apiece. Four states field more than ten competing carriers —
Texas and Florida (15 each), Wisconsin (12), and Ohio (11). A deep
issuer bench does not by itself buy cheap silver: Ohio pairs its 11
carriers with one of the lowest benchmark silver premiums in the table
above, while Texas and Florida sit among the most expensive silver
markets despite leading the issuer count.

## The CSR deductible cliff

Silver plans on the FFM come in four flavours: a standard silver plan
and three cost-sharing-reduction (CSR) variants offered to enrollees
whose household income falls below 250% of the federal poverty level.
The variants leave the premium untouched but slash the deductible and
out-of-pocket maximum — the discontinuity between the "73%" variant
(200–250% FPL) and the standard silver plan is the cliff households
face when income rises past the 250% threshold.

```sql csr_deductibles
select
    csr_label,
    plans,
    plan_county_offerings,
    avg_deductible_individual,
    median_deductible_individual,
    avg_moop_individual,
    median_moop_individual,
    csr_sort
from cms.qhp_csr_deductibles
order by csr_sort desc
```

<BarChart
  data={csr_deductibles}
  x=csr_label
  y=median_deductible_individual
  title="Median individual medical deductible, silver plans by CSR level"
  yFmt=usd0
  sort=false
  swapXY=true
/>

<DataTable data={csr_deductibles}>
  <Column id=csr_label title="Cost-sharing tier" wrap=true />
  <Column id=plans title="Plans" fmt=num0 />
  <Column id=median_deductible_individual title="Median deductible" fmt=usd0 />
  <Column id=avg_deductible_individual title="Mean deductible" fmt=usd0 />
  <Column id=median_moop_individual title="Median MOOP" fmt=usd0 />
  <Column id=avg_moop_individual title="Mean MOOP" fmt=usd0 />
</DataTable>

The 94% CSR variant (100–150% FPL) has a median deductible of $0 and
the median 87% variant plan is $700 — jumping to $3,000 at the 73%
variant and $6,000 at standard silver. A household that gains enough
income to cross from 200% to 250% FPL is auto-enrolled into a plan
whose deductible is roughly double, without any change to the plan
they've chosen or the premium they pay before subsidies.

## Child and dental coverage

### Child-only enrollment

Every individual-market medical plan on the FFM allows child-only
enrollment. Dental issuers split between plans that accept both adults
and children and a smaller pool of dedicated child-only dental plans.

```sql child_only
select
    product,
    child_only_offering,
    plans
from cms.qhp_child_only
```

<BarChart
  data={child_only}
  x=child_only_offering
  y=plans
  series=product
  type=grouped
  swapXY=true
  title="Plans by child-only offering, individual market"
  yFmt=num0
/>

### Dental premiums

Stand-alone dental plans come in two actuarial tiers on the FFM.
**High** plans cover a larger share of expected costs (roughly 85% AV
in the CMS template) at a higher premium; **Low** plans cover less
(roughly 70% AV). Child dental is an essential health benefit under
the ACA, and pediatric dental is embedded in nearly every FFM medical
plan — the stand-alone dental market shown here layers on top of that.

```sql dental_summary
select
    metal_level,
    scenario_label,
    plans,
    median_premium,
    avg_premium,
    min_premium,
    max_premium,
    scenario_sort
from cms.qhp_dental_summary
order by metal_level, scenario_sort
```

<BarChart
  data={dental_summary}
  x=scenario_label
  y=median_premium
  series=metal_level
  type=grouped
  title="Median stand-alone dental premium by tier and enrollee"
  yFmt=usd0
/>

<DataTable data={dental_summary} rows=6>
  <Column id=metal_level title="Tier" />
  <Column id=scenario_label title="Enrollee" />
  <Column id=plans title="Plans" fmt=num0 />
  <Column id=median_premium title="Median" fmt=usd2 />
  <Column id=avg_premium title="Mean" fmt=usd2 />
  <Column id=min_premium title="Min" fmt=usd2 />
  <Column id=max_premium title="Max" fmt=usd2 />
</DataTable>

The tier gap is real: median child dental runs about $37/month at the
High tier vs $26 at Low, and adult dental medians land at $33 and $18
respectively. Neither is subsidised through premium tax credits.

## Caveats

- **FFM only.** The <Value data={headline} column=states fmt=num0 />
  states covered here are the ones that use HealthCare.gov. Roughly a
  third of the U.S. individual-market population enrols through a
  state-based exchange that publishes its own landscape file, and
  those enrollees, plans, and issuers are entirely absent.
- **List prices, not paid prices.** Every premium above is the plan's
  gross monthly premium. Roughly 90% of FFM enrollees receive advance
  premium tax credits that reduce what they actually pay; that subsidy
  math depends on household income and the benchmark silver premium
  in their county and is not applied here.
- **Point-in-time landscape.** All figures reflect the CMS landscape
  file `as_of`
  <Value data={headline} column=plan_as_of fmt=longdate />. Issuers
  can file rate revisions through open enrolment, and plan availability
  can change between now and coverage effective date.
- **Plan-availability concentration.** The HHI reported above weights
  each plan-county offering equally; it is not an enrollment-share
  concentration measure. CMS does not publish plan-level enrolment
  counts in the landscape data, so a true market-share HHI would
  require the SBM-and-FFM combined effectuated-enrolment PUF.
- **SHOP nearly empty.** Small-group SHOP plans exist for only four
  states in the medical file (AL, MT, NH, WI) and one on the dental
  side (WI). SHOP is excluded from every state chart above; the SHOP
  totals in the headline are for reference only.
- **CSR variants apply only to silver plans.** The cost-sharing tiers
  in the CSR-deductible section exist only in the silver metal band;
  bronze, gold, and platinum plans carry only the standard cost-sharing
  structure regardless of enrolee income.
