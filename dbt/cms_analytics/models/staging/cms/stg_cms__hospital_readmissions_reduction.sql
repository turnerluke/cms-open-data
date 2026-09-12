with source as (

    select * from {{ source('cms_raw', 'cms_hospital_readmissions_reduction') }}

),

renamed as (

    select
        -- identifiers
        -- CCN join key, conformed as in
        -- stg_cms__hospital_general_information
        upper(trim(facility_id)) as facility_id,
        trim(facility_name) as facility_name,
        trim(state) as state,

        -- measure — 6 values, all suffixed `-HRRP`
        trim(measure_name) as measure_name,

        -- volumes
        -- `number_of_discharges` carries `'Not Available'` for 10,088
        -- of 18,330 rows (~55%); above the 50% threshold that would
        -- justify a raw-text companion, so `footnote` (below) is kept
        -- to explain the suppression.
        try_cast(number_of_discharges as int) as number_of_discharges,

        -- CMS suppression footnote codes; empty string is the "no
        -- footnote" state and becomes `NULL` so `not_null` on this
        -- column would (correctly) fail.
        nullif(trim(footnote), '') as footnote,

        -- results — `'N/A'` (6,610 rows, 36%) becomes `NULL` via
        -- try_cast for all three risk-adjusted result columns
        try_cast(excess_readmission_ratio as decimal(10, 4)) as excess_readmission_ratio,
        try_cast(predicted_readmission_rate as decimal(10, 4)) as predicted_readmission_rate,
        try_cast(expected_readmission_rate as decimal(10, 4)) as expected_readmission_rate,

        -- readmissions carries a distinct sentinel `'Too Few to
        -- Report'` (3,683 rows) that is informative suppression from
        -- small counts, separate from the `'N/A'` ineligible state
        -- (6,610 rows). Preserve the small-count signal as a boolean
        -- so downstream marts can distinguish the two.
        trim(number_of_readmissions) = 'Too Few to Report' as is_too_few_to_report,
        try_cast(number_of_readmissions as int) as number_of_readmissions,

        -- measurement period — single window 07/01/2021–06/30/2024
        -- across every row in this vintage
        cast(try_strptime(start_date, '%m/%d/%Y') as date) as start_date,
        cast(try_strptime(end_date, '%m/%d/%Y') as date) as end_date

    from source

)

select * from renamed
