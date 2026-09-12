{#-
    Premium scenarios published on each of the four QHP landscape files
    (individual × SHOP by medical × dental). Each source row is one
    plan × county with 37 wide premium-scenario columns; this model
    unpivots those into a long fact keyed on the scenario name so
    Evidence can group / compare on the sample family shape and age
    without knowing the column list.

    Scenarios are decomposed into (`family_structure`, `primary_age`)
    columns rather than parsed downstream: `family_structure` names the
    sample household (`child`, `individual`, `couple`,
    `couple_plus_1_child`, ..., `individual_plus_3_or_more_children`)
    and `primary_age` is the CMS-published sample age in years. For the
    `premium_child_age_0_14` scenario CMS quotes a single flat rate
    covering the 0-14 age band; we encode that as
    `family_structure = 'child'` with `primary_age = 14` (top of the
    band, keeping the column a SMALLINT) and set `is_child_only_scenario
    = TRUE` so consumers who care about the child-only cases can filter
    without regexing the label. `premium_child_age_18` becomes
    `family_structure = 'child'` at `primary_age = 18`.
-#}

{%- set scenarios = [
    ('premium_child_age_0_14',                                     'child_age_0_14',                                     'child',                                     14, true),
    ('premium_child_age_18',                                       'child_age_18',                                       'child',                                     18, true),
    ('premium_adult_individual_age_21',                            'individual_age_21',                                  'individual',                                21, false),
    ('premium_adult_individual_age_27',                            'individual_age_27',                                  'individual',                                27, false),
    ('premium_adult_individual_age_30',                            'individual_age_30',                                  'individual',                                30, false),
    ('premium_adult_individual_age_40',                            'individual_age_40',                                  'individual',                                40, false),
    ('premium_adult_individual_age_50',                            'individual_age_50',                                  'individual',                                50, false),
    ('premium_adult_individual_age_60',                            'individual_age_60',                                  'individual',                                60, false),
    ('premium_couple_age_21',                                      'couple_age_21',                                      'couple',                                    21, false),
    ('premium_couple_age_30',                                      'couple_age_30',                                      'couple',                                    30, false),
    ('premium_couple_age_40',                                      'couple_age_40',                                      'couple',                                    40, false),
    ('premium_couple_age_50',                                      'couple_age_50',                                      'couple',                                    50, false),
    ('premium_couple_age_60',                                      'couple_age_60',                                      'couple',                                    60, false),
    ('premium_couple_plus_1_child_age_21',                         'couple_plus_1_child_age_21',                         'couple_plus_1_child',                       21, false),
    ('premium_couple_plus_1_child_age_30',                         'couple_plus_1_child_age_30',                         'couple_plus_1_child',                       30, false),
    ('premium_couple_plus_1_child_age_40',                         'couple_plus_1_child_age_40',                         'couple_plus_1_child',                       40, false),
    ('premium_couple_plus_1_child_age_50',                         'couple_plus_1_child_age_50',                         'couple_plus_1_child',                       50, false),
    ('premium_couple_plus_2_children_age_21',                      'couple_plus_2_children_age_21',                      'couple_plus_2_children',                    21, false),
    ('premium_couple_plus_2_children_age_30',                      'couple_plus_2_children_age_30',                      'couple_plus_2_children',                    30, false),
    ('premium_couple_plus_2_children_age_40',                      'couple_plus_2_children_age_40',                      'couple_plus_2_children',                    40, false),
    ('premium_couple_plus_2_children_age_50',                      'couple_plus_2_children_age_50',                      'couple_plus_2_children',                    50, false),
    ('premium_couple_plus_3_or_more_children_age_21',              'couple_plus_3_or_more_children_age_21',              'couple_plus_3_or_more_children',            21, false),
    ('premium_couple_plus_3_or_more_children_age_30',              'couple_plus_3_or_more_children_age_30',              'couple_plus_3_or_more_children',            30, false),
    ('premium_couple_plus_3_or_more_children_age_40',              'couple_plus_3_or_more_children_age_40',              'couple_plus_3_or_more_children',            40, false),
    ('premium_couple_plus_3_or_more_children_age_50',              'couple_plus_3_or_more_children_age_50',              'couple_plus_3_or_more_children',            50, false),
    ('premium_individual_plus_1_child_age_21',                     'individual_plus_1_child_age_21',                     'individual_plus_1_child',                   21, false),
    ('premium_individual_plus_1_child_age_30',                     'individual_plus_1_child_age_30',                     'individual_plus_1_child',                   30, false),
    ('premium_individual_plus_1_child_age_40',                     'individual_plus_1_child_age_40',                     'individual_plus_1_child',                   40, false),
    ('premium_individual_plus_1_child_age_50',                     'individual_plus_1_child_age_50',                     'individual_plus_1_child',                   50, false),
    ('premium_individual_plus_2_children_age_21',                  'individual_plus_2_children_age_21',                  'individual_plus_2_children',                21, false),
    ('premium_individual_plus_2_children_age_30',                  'individual_plus_2_children_age_30',                  'individual_plus_2_children',                30, false),
    ('premium_individual_plus_2_children_age_40',                  'individual_plus_2_children_age_40',                  'individual_plus_2_children',                40, false),
    ('premium_individual_plus_2_children_age_50',                  'individual_plus_2_children_age_50',                  'individual_plus_2_children',                50, false),
    ('premium_individual_plus_3_or_more_children_age_21',          'individual_plus_3_or_more_children_age_21',          'individual_plus_3_or_more_children',        21, false),
    ('premium_individual_plus_3_or_more_children_age_30',          'individual_plus_3_or_more_children_age_30',          'individual_plus_3_or_more_children',        30, false),
    ('premium_individual_plus_3_or_more_children_age_40',          'individual_plus_3_or_more_children_age_40',          'individual_plus_3_or_more_children',        40, false),
    ('premium_individual_plus_3_or_more_children_age_50',          'individual_plus_3_or_more_children_age_50',          'individual_plus_3_or_more_children',        50, false),
] -%}

with unioned as (

    -- One row per plan × county across the four QHP landscape files.
    -- Each `stg_cms__qhp_landscape_*_2026` model already carries
    -- `plan_year`, `market`, `product`, `metal_level`, and
    -- `rating_area`; the wide premium columns are identically named
    -- across the four files, so a `union all by name` of the 37 +
    -- carry-through columns is safe.
    select
        plan_id,
        fips_county_code,
        plan_year,
        market,
        product,
        metal_level,
        rating_area,
        premium_child_age_0_14,
        premium_child_age_18,
        premium_adult_individual_age_21,
        premium_adult_individual_age_27,
        premium_adult_individual_age_30,
        premium_adult_individual_age_40,
        premium_adult_individual_age_50,
        premium_adult_individual_age_60,
        premium_couple_age_21,
        premium_couple_age_30,
        premium_couple_age_40,
        premium_couple_age_50,
        premium_couple_age_60,
        premium_couple_plus_1_child_age_21,
        premium_couple_plus_1_child_age_30,
        premium_couple_plus_1_child_age_40,
        premium_couple_plus_1_child_age_50,
        premium_couple_plus_2_children_age_21,
        premium_couple_plus_2_children_age_30,
        premium_couple_plus_2_children_age_40,
        premium_couple_plus_2_children_age_50,
        premium_couple_plus_3_or_more_children_age_21,
        premium_couple_plus_3_or_more_children_age_30,
        premium_couple_plus_3_or_more_children_age_40,
        premium_couple_plus_3_or_more_children_age_50,
        premium_individual_plus_1_child_age_21,
        premium_individual_plus_1_child_age_30,
        premium_individual_plus_1_child_age_40,
        premium_individual_plus_1_child_age_50,
        premium_individual_plus_2_children_age_21,
        premium_individual_plus_2_children_age_30,
        premium_individual_plus_2_children_age_40,
        premium_individual_plus_2_children_age_50,
        premium_individual_plus_3_or_more_children_age_21,
        premium_individual_plus_3_or_more_children_age_30,
        premium_individual_plus_3_or_more_children_age_40,
        premium_individual_plus_3_or_more_children_age_50
    from {{ ref('stg_cms__qhp_landscape_individual_medical_2026') }}
    union all
    select
        plan_id,
        fips_county_code,
        plan_year,
        market,
        product,
        metal_level,
        rating_area,
        premium_child_age_0_14,
        premium_child_age_18,
        premium_adult_individual_age_21,
        premium_adult_individual_age_27,
        premium_adult_individual_age_30,
        premium_adult_individual_age_40,
        premium_adult_individual_age_50,
        premium_adult_individual_age_60,
        premium_couple_age_21,
        premium_couple_age_30,
        premium_couple_age_40,
        premium_couple_age_50,
        premium_couple_age_60,
        premium_couple_plus_1_child_age_21,
        premium_couple_plus_1_child_age_30,
        premium_couple_plus_1_child_age_40,
        premium_couple_plus_1_child_age_50,
        premium_couple_plus_2_children_age_21,
        premium_couple_plus_2_children_age_30,
        premium_couple_plus_2_children_age_40,
        premium_couple_plus_2_children_age_50,
        premium_couple_plus_3_or_more_children_age_21,
        premium_couple_plus_3_or_more_children_age_30,
        premium_couple_plus_3_or_more_children_age_40,
        premium_couple_plus_3_or_more_children_age_50,
        premium_individual_plus_1_child_age_21,
        premium_individual_plus_1_child_age_30,
        premium_individual_plus_1_child_age_40,
        premium_individual_plus_1_child_age_50,
        premium_individual_plus_2_children_age_21,
        premium_individual_plus_2_children_age_30,
        premium_individual_plus_2_children_age_40,
        premium_individual_plus_2_children_age_50,
        premium_individual_plus_3_or_more_children_age_21,
        premium_individual_plus_3_or_more_children_age_30,
        premium_individual_plus_3_or_more_children_age_40,
        premium_individual_plus_3_or_more_children_age_50
    from {{ ref('stg_cms__qhp_landscape_individual_dental_2026') }}
    union all
    select
        plan_id,
        fips_county_code,
        plan_year,
        market,
        product,
        metal_level,
        rating_area,
        premium_child_age_0_14,
        premium_child_age_18,
        premium_adult_individual_age_21,
        premium_adult_individual_age_27,
        premium_adult_individual_age_30,
        premium_adult_individual_age_40,
        premium_adult_individual_age_50,
        premium_adult_individual_age_60,
        premium_couple_age_21,
        premium_couple_age_30,
        premium_couple_age_40,
        premium_couple_age_50,
        premium_couple_age_60,
        premium_couple_plus_1_child_age_21,
        premium_couple_plus_1_child_age_30,
        premium_couple_plus_1_child_age_40,
        premium_couple_plus_1_child_age_50,
        premium_couple_plus_2_children_age_21,
        premium_couple_plus_2_children_age_30,
        premium_couple_plus_2_children_age_40,
        premium_couple_plus_2_children_age_50,
        premium_couple_plus_3_or_more_children_age_21,
        premium_couple_plus_3_or_more_children_age_30,
        premium_couple_plus_3_or_more_children_age_40,
        premium_couple_plus_3_or_more_children_age_50,
        premium_individual_plus_1_child_age_21,
        premium_individual_plus_1_child_age_30,
        premium_individual_plus_1_child_age_40,
        premium_individual_plus_1_child_age_50,
        premium_individual_plus_2_children_age_21,
        premium_individual_plus_2_children_age_30,
        premium_individual_plus_2_children_age_40,
        premium_individual_plus_2_children_age_50,
        premium_individual_plus_3_or_more_children_age_21,
        premium_individual_plus_3_or_more_children_age_30,
        premium_individual_plus_3_or_more_children_age_40,
        premium_individual_plus_3_or_more_children_age_50
    from {{ ref('stg_cms__qhp_landscape_shop_medical_2026') }}
    union all
    select
        plan_id,
        fips_county_code,
        plan_year,
        market,
        product,
        metal_level,
        rating_area,
        premium_child_age_0_14,
        premium_child_age_18,
        premium_adult_individual_age_21,
        premium_adult_individual_age_27,
        premium_adult_individual_age_30,
        premium_adult_individual_age_40,
        premium_adult_individual_age_50,
        premium_adult_individual_age_60,
        premium_couple_age_21,
        premium_couple_age_30,
        premium_couple_age_40,
        premium_couple_age_50,
        premium_couple_age_60,
        premium_couple_plus_1_child_age_21,
        premium_couple_plus_1_child_age_30,
        premium_couple_plus_1_child_age_40,
        premium_couple_plus_1_child_age_50,
        premium_couple_plus_2_children_age_21,
        premium_couple_plus_2_children_age_30,
        premium_couple_plus_2_children_age_40,
        premium_couple_plus_2_children_age_50,
        premium_couple_plus_3_or_more_children_age_21,
        premium_couple_plus_3_or_more_children_age_30,
        premium_couple_plus_3_or_more_children_age_40,
        premium_couple_plus_3_or_more_children_age_50,
        premium_individual_plus_1_child_age_21,
        premium_individual_plus_1_child_age_30,
        premium_individual_plus_1_child_age_40,
        premium_individual_plus_1_child_age_50,
        premium_individual_plus_2_children_age_21,
        premium_individual_plus_2_children_age_30,
        premium_individual_plus_2_children_age_40,
        premium_individual_plus_2_children_age_50,
        premium_individual_plus_3_or_more_children_age_21,
        premium_individual_plus_3_or_more_children_age_30,
        premium_individual_plus_3_or_more_children_age_40,
        premium_individual_plus_3_or_more_children_age_50
    from {{ ref('stg_cms__qhp_landscape_shop_dental_2026') }}

),

unpivoted as (

    {% for column, label, family, age, is_child_only in scenarios %}
        select
            plan_id,
            fips_county_code,
            plan_year,
            market,
            product,
            metal_level,
            rating_area,
            '{{ label }}' as scenario,
            '{{ family }}' as family_structure,
            cast({{ age }} as smallint) as primary_age,
            {{ 'true' if is_child_only else 'false' }} as is_child_only_scenario,
            {{ column }} as monthly_premium
        from unioned
        {% if not loop.last %}union all{% endif %}
    {% endfor %}

),

final as (

    -- Drop rows where the source scenario cell is NULL (232,050 of
    -- 5,592,920 unpivoted rows in the PY2026 vintage — 6,630
    -- child-only individual-dental plans × 35 non-child scenarios).
    -- Zero-dollar premiums do not exist in this vintage on any of the
    -- four files, so no `!= 0` filter is applied; if a future vintage
    -- ships a legitimate $0 (e.g. a child-only rider bundled with a
    -- medical plan) it will land here rather than being silently
    -- discarded.
    select
        u.*,
        -- Snapshot vintage: max upstream `modified` across the four
        -- QHP dataset keys, matching `dim_qhp_plan.as_of` / `dim_county.as_of`
        -- so a plan × county join carries one consistent `as_of`.
        -- Scalar subquery keeps a missing sidecar surfacing as NULL
        -- (caught by not_null) rather than dropping rows.
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
    from unpivoted as u
    where u.monthly_premium is not null

)

select * from final
