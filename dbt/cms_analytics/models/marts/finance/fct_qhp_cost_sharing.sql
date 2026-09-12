{#-
    Deductibles, out-of-pocket maximums, and copay/coinsurance
    schedules for every certified Qualified Health Plan (QHP), unpivoted
    from the wide cost-sharing blocks of the four
    `stg_cms__qhp_landscape_*_2026` staging models into one long fact
    keyed on the cost-sharing variant.

    Grain: (`plan_id`, `fips_county_code`, `csr_variant`).

    ## Variant encoding

    `csr_variant` mirrors the source-column suffix so the mapping stays
    grep-friendly: `'standard'` (the plan's default cost-sharing
    schedule, present on every plan × county row across all four
    files) and `'73_percent'` / `'87_percent'` / `'94_percent'` (the
    Silver-only cost-sharing reduction (CSR) variants CMS publishes on
    the **individual-market medical** file). CSR rates raise the
    actuarial value of a Silver plan for consumers below specific
    income thresholds, so 94-percent CSR always carries the leanest
    cost sharing.

    ## Union style

    The four QHP files carry structurally different cost-sharing
    columns (individual medical has all four variants; shop medical
    has only Standard; the two dental files replace the medical /
    drug blocks with a single dental block and drop the nine copay
    columns), so `dbt_utils.union_relations` doesn't fit — the wide
    columns aren't parallel across files. Instead, each source is
    unpivoted to the long shape in its own CTE and the four long
    tables are `union all`-ed at the end. The individual-medical CTE
    uses a Jinja loop over the four variants (`standard`, `73_percent`,
    `87_percent`, `94_percent`) so the four CSR blocks share a single
    column list rather than being hand-typed four times.

    ## Which rows emit

    - Every plan × county emits a `'standard'` row (151,160 rows —
      one per staging source row).
    - Individual-medical Silver plans additionally emit three CSR
      rows (33,537 each). Non-Silver individual-medical rows and all
      SHOP / dental rows carry no CSR block and emit no CSR rows.
    - Expected total: 151,160 + 3 × 33,537 = 251,771 rows.

    ## Column shape

    Numeric money columns (medical / drug / dental deductibles and
    MOOPs, each with individual / family / family-per-person tiers)
    stay `NULL` where the source file / product doesn't carry them:
    dental deductibles are NULL on medical rows and vice versa; drug
    columns are NULL on dental rows and on medical rows where the
    plan's drug benefit is integrated with the medical accumulator
    (see below). Copay / coinsurance columns are trimmed text
    (medical only — NULL on dental rows), passed through unparsed so
    consumers can decide whether a value like
    `$25 Copay with deductible and 20% Coinsurance after deductible`
    should be split into structured fields.

    ## Integrated drug benefits

    `drug_benefits_integrated` is the per-variant boolean from
    staging. `TRUE` means the plan runs pharmacy spend through the
    same accumulator as medical spend (so `drug_deductible_*` and
    `drug_moop_*` land as `NULL` on that row — a real product-design
    signal, not missing data). In the PY2026 vintage every medical
    plan is integrated on every populated variant, so all
    `drug_moop_*` numerics are `NULL` on medical rows. `NULL` on
    dental rows (dental has no pharmacy block).
-#}

{%- set variants = [
    ('standard',    'standard'),
    ('73_percent',  '73_percent'),
    ('87_percent',  '87_percent'),
    ('94_percent',  '94_percent'),
] -%}

with individual_medical as (

    -- All four cost-sharing variants share the same column shape on
    -- the individual-medical file, so we generate one SELECT per
    -- variant and filter to rows where the variant's block is
    -- populated. `medical_moop_individual_{variant}` is the canonical
    -- block-populated signal: it's numeric-typed, non-optional per
    -- HHS's CSR-plan-design rules, and populated on 100% of Silver
    -- rows for every CSR variant (0 nulls per staging query). For
    -- the `standard` variant it is populated on 100% of rows.
    {% for variant, suffix in variants %}
        select
            plan_id,
            fips_county_code,
            plan_year,
            market,
            product,
            metal_level,
            rating_area,
            '{{ variant }}' as csr_variant,
            medical_deductible_individual_{{ suffix }} as medical_deductible_individual,
            medical_deductible_family_{{ suffix }} as medical_deductible_family,
            medical_deductible_family_per_person_{{ suffix }} as medical_deductible_family_per_person,
            drug_deductible_individual_{{ suffix }} as drug_deductible_individual,
            drug_deductible_family_{{ suffix }} as drug_deductible_family,
            drug_deductible_family_per_person_{{ suffix }} as drug_deductible_family_per_person,
            medical_moop_individual_{{ suffix }} as medical_moop_individual,
            medical_moop_family_{{ suffix }} as medical_moop_family,
            medical_moop_family_per_person_{{ suffix }} as medical_moop_family_per_person,
            drug_moop_individual_{{ suffix }} as drug_moop_individual,
            drug_moop_family_{{ suffix }} as drug_moop_family,
            drug_moop_family_per_person_{{ suffix }} as drug_moop_family_per_person,
            cast(null as decimal(12, 2)) as dental_deductible_individual,
            cast(null as decimal(12, 2)) as dental_deductible_family,
            cast(null as decimal(12, 2)) as dental_deductible_family_per_person,
            cast(null as decimal(12, 2)) as dental_moop_individual,
            cast(null as decimal(12, 2)) as dental_moop_family,
            cast(null as decimal(12, 2)) as dental_moop_family_per_person,
            drug_benefits_integrated_{{ suffix }} as drug_benefits_integrated,
            primary_care_physician_{{ suffix }} as copay_primary_care,
            specialist_{{ suffix }} as copay_specialist,
            emergency_room_{{ suffix }} as copay_emergency_room,
            inpatient_facility_{{ suffix }} as copay_inpatient_facility,
            inpatient_physician_{{ suffix }} as copay_inpatient_physician,
            generic_drugs_{{ suffix }} as copay_generic_drugs,
            preferred_brand_drugs_{{ suffix }} as copay_preferred_brand_drugs,
            non_preferred_brand_drugs_{{ suffix }} as copay_non_preferred_brand_drugs,
            specialty_drugs_{{ suffix }} as copay_specialty_drugs
        from {{ ref('stg_cms__qhp_landscape_individual_medical_2026') }}
        {% if variant != 'standard' -%}
            where medical_moop_individual_{{ suffix }} is not null
        {%- endif %}
        {% if not loop.last %}union all{% endif %}
    {% endfor %}

),

shop_medical as (

    -- SHOP medical carries only the Standard block (no CSR — CSRs are
    -- an individual-market program).
    select
        plan_id,
        fips_county_code,
        plan_year,
        market,
        product,
        metal_level,
        rating_area,
        'standard' as csr_variant,
        medical_deductible_individual_standard as medical_deductible_individual,
        medical_deductible_family_standard as medical_deductible_family,
        medical_deductible_family_per_person_standard as medical_deductible_family_per_person,
        drug_deductible_individual_standard as drug_deductible_individual,
        drug_deductible_family_standard as drug_deductible_family,
        drug_deductible_family_per_person_standard as drug_deductible_family_per_person,
        medical_moop_individual_standard as medical_moop_individual,
        medical_moop_family_standard as medical_moop_family,
        medical_moop_family_per_person_standard as medical_moop_family_per_person,
        drug_moop_individual_standard as drug_moop_individual,
        drug_moop_family_standard as drug_moop_family,
        drug_moop_family_per_person_standard as drug_moop_family_per_person,
        cast(null as decimal(12, 2)) as dental_deductible_individual,
        cast(null as decimal(12, 2)) as dental_deductible_family,
        cast(null as decimal(12, 2)) as dental_deductible_family_per_person,
        cast(null as decimal(12, 2)) as dental_moop_individual,
        cast(null as decimal(12, 2)) as dental_moop_family,
        cast(null as decimal(12, 2)) as dental_moop_family_per_person,
        drug_benefits_integrated_standard as drug_benefits_integrated,
        primary_care_physician_standard as copay_primary_care,
        specialist_standard as copay_specialist,
        emergency_room_standard as copay_emergency_room,
        inpatient_facility_standard as copay_inpatient_facility,
        inpatient_physician_standard as copay_inpatient_physician,
        generic_drugs_standard as copay_generic_drugs,
        preferred_brand_drugs_standard as copay_preferred_brand_drugs,
        non_preferred_brand_drugs_standard as copay_non_preferred_brand_drugs,
        specialty_drugs_standard as copay_specialty_drugs
    from {{ ref('stg_cms__qhp_landscape_shop_medical_2026') }}

),

individual_dental as (

    -- Dental files replace medical / drug blocks with a single dental
    -- block and drop the nine copay text columns. Only the Standard
    -- variant exists.
    select
        plan_id,
        fips_county_code,
        plan_year,
        market,
        product,
        metal_level,
        rating_area,
        'standard' as csr_variant,
        cast(null as decimal(12, 2)) as medical_deductible_individual,
        cast(null as decimal(12, 2)) as medical_deductible_family,
        cast(null as decimal(12, 2)) as medical_deductible_family_per_person,
        cast(null as decimal(12, 2)) as drug_deductible_individual,
        cast(null as decimal(12, 2)) as drug_deductible_family,
        cast(null as decimal(12, 2)) as drug_deductible_family_per_person,
        cast(null as decimal(12, 2)) as medical_moop_individual,
        cast(null as decimal(12, 2)) as medical_moop_family,
        cast(null as decimal(12, 2)) as medical_moop_family_per_person,
        cast(null as decimal(12, 2)) as drug_moop_individual,
        cast(null as decimal(12, 2)) as drug_moop_family,
        cast(null as decimal(12, 2)) as drug_moop_family_per_person,
        dental_deductible_individual_standard as dental_deductible_individual,
        dental_deductible_family_standard as dental_deductible_family,
        dental_deductible_family_per_person_standard as dental_deductible_family_per_person,
        dental_moop_individual_standard as dental_moop_individual,
        dental_moop_family_standard as dental_moop_family,
        dental_moop_family_per_person_standard as dental_moop_family_per_person,
        cast(null as boolean) as drug_benefits_integrated,
        cast(null as varchar) as copay_primary_care,
        cast(null as varchar) as copay_specialist,
        cast(null as varchar) as copay_emergency_room,
        cast(null as varchar) as copay_inpatient_facility,
        cast(null as varchar) as copay_inpatient_physician,
        cast(null as varchar) as copay_generic_drugs,
        cast(null as varchar) as copay_preferred_brand_drugs,
        cast(null as varchar) as copay_non_preferred_brand_drugs,
        cast(null as varchar) as copay_specialty_drugs
    from {{ ref('stg_cms__qhp_landscape_individual_dental_2026') }}

),

shop_dental as (

    select
        plan_id,
        fips_county_code,
        plan_year,
        market,
        product,
        metal_level,
        rating_area,
        'standard' as csr_variant,
        cast(null as decimal(12, 2)) as medical_deductible_individual,
        cast(null as decimal(12, 2)) as medical_deductible_family,
        cast(null as decimal(12, 2)) as medical_deductible_family_per_person,
        cast(null as decimal(12, 2)) as drug_deductible_individual,
        cast(null as decimal(12, 2)) as drug_deductible_family,
        cast(null as decimal(12, 2)) as drug_deductible_family_per_person,
        cast(null as decimal(12, 2)) as medical_moop_individual,
        cast(null as decimal(12, 2)) as medical_moop_family,
        cast(null as decimal(12, 2)) as medical_moop_family_per_person,
        cast(null as decimal(12, 2)) as drug_moop_individual,
        cast(null as decimal(12, 2)) as drug_moop_family,
        cast(null as decimal(12, 2)) as drug_moop_family_per_person,
        dental_deductible_individual_standard as dental_deductible_individual,
        dental_deductible_family_standard as dental_deductible_family,
        dental_deductible_family_per_person_standard as dental_deductible_family_per_person,
        dental_moop_individual_standard as dental_moop_individual,
        dental_moop_family_standard as dental_moop_family,
        dental_moop_family_per_person_standard as dental_moop_family_per_person,
        cast(null as boolean) as drug_benefits_integrated,
        cast(null as varchar) as copay_primary_care,
        cast(null as varchar) as copay_specialist,
        cast(null as varchar) as copay_emergency_room,
        cast(null as varchar) as copay_inpatient_facility,
        cast(null as varchar) as copay_inpatient_physician,
        cast(null as varchar) as copay_generic_drugs,
        cast(null as varchar) as copay_preferred_brand_drugs,
        cast(null as varchar) as copay_non_preferred_brand_drugs,
        cast(null as varchar) as copay_specialty_drugs
    from {{ ref('stg_cms__qhp_landscape_shop_dental_2026') }}

),

unioned as (

    select * from individual_medical
    union all
    select * from shop_medical
    union all
    select * from individual_dental
    union all
    select * from shop_dental

),

final as (

    select
        u.*,
        -- Snapshot vintage: max upstream `modified` across the four
        -- QHP dataset keys, matching `dim_qhp_plan.as_of`,
        -- `dim_county.as_of`, and `fct_qhp_premiums.as_of` so a
        -- plan × county join carries one consistent `as_of`. Scalar
        -- subquery keeps a missing sidecar surfacing as NULL (caught
        -- by not_null) rather than dropping rows.
        (
            select max(vintages.modified) as modified
            from {{ ref('stg_cms__dataset_vintages') }} as vintages
            where vintages.dataset_key in (
                'qhp_landscape_individual_medical_2026',
                'qhp_landscape_individual_dental_2026',
                'qhp_landscape_shop_medical_2026',
                'qhp_landscape_shop_dental_2026'
            )
        ) as as_of
    from unioned as u

)

select * from final
