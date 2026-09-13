with source as (

    select * from {{ source('cms_raw', 'cms_medicaid_state_drug_utilization_2023') }}

),

renamed as (

    select
        -- utilization channel — the file interleaves two:
        --   'FFSU' — Fee-For-Service Utilization (2,539,160 rows)
        --   'MCOU' — Managed-Care Organization Utilization (2,787,426)
        -- CMS publishes both channels side-by-side; downstream marts
        -- that want "total Medicaid" must sum across both.
        trim("Utilization Type") as utilization_type,

        -- two-letter state code. 53 distinct values: 50 states + DC +
        -- PR + a pseudo-state `XX` that carries the CMS-computed
        -- national aggregate row (321,345 rows). `XX` is NOT the
        -- straight sum of the state rows — states blank-suppress
        -- their five measure columns whenever prescriptions are 1–10
        -- (~51.5% of state rows), while `XX` re-adds those suppressed
        -- values from CMS's unsuppressed source. Every disclosed-state
        -- XX cross-check landed at XX >= sum(states); equality is
        -- dominated by cells where no state was suppressed (3,014 of
        -- the 3,167 equal cells; the other 153 net out). Downstream
        -- marts should either filter `state = 'XX'` for national
        -- totals or `state != 'XX'` for state-level roll-ups — never
        -- mix.
        trim(state) as state,

        -- 11-character National Drug Code (labeler-product-package).
        -- Always populated; 53,205 distinct values. The three
        -- components are also published as separate columns and
        -- concatenate exactly (verified: 0 rows where
        -- `NDC != labeler_code || product_code || package_size`).
        trim(ndc) as ndc,
        trim("Labeler Code") as labeler_code,
        trim("Product Code") as product_code,
        trim("Package Size") as package_size,

        -- reporting period. All rows carry `year = 2023`; quarters
        -- 1–4 are all present and roughly balanced (1,319,180 –
        -- 1,358,311 rows each). Kept quoted at the source side because
        -- the raw CMS headers are title-cased; aliased to snake_case
        -- non-reserved names.
        cast(year as integer) as calendar_year, -- noqa: RF06
        cast(quarter as integer) as calendar_quarter, -- noqa: RF06

        -- CMS suppression flag. `true` when prescriptions are 1–10
        -- and CMS blanks out all five measure columns; `false` when
        -- disclosed. Verified: every suppressed row has all five
        -- measures `NULL`, and every disclosed row has all five
        -- measures populated — no exceptions. This staging file
        -- surfaces the flag alongside the measures so downstream
        -- consumers can distinguish "not reported (suppressed)" from
        -- any zero that might legitimately appear.
        "Suppression Used" as suppression_used,

        -- product name from the CMS file. Truncated at 10 characters
        -- (94% of non-blank values are 9-10 chars; lengths run 1-10),
        -- so it is NOT a reliable drug name — e.g. `'0.9% NACL '` and
        -- `'0.9% Sodiu'` co-exist as truncations of longer names.
        -- 32,704 of the 53,205 NDCs (61%) map to more than one
        -- distinct non-blank truncated product name. 8,400 rows carry
        -- an all-blank product name;
        -- those are nulled out here. Any drug-dimension joining in
        -- downstream marts must use the NDC (or its labeler/product
        -- components), not `product_name`.
        nullif(trim("Product Name"), '') as product_name,

        -- five measure columns. All five are `NULL` iff
        -- `suppression_used = true`; when disclosed they are always
        -- populated (all try_cast-parseable to DOUBLE, no unparseable
        -- rows). The identity
        -- `total_amount_reimbursed = medicaid_amount_reimbursed +
        --  non_medicaid_amount_reimbursed`
        -- holds on 100% of disclosed rows (0 violations at 0.01
        -- tolerance). All values are non-negative.
        --
        -- `Units Reimbursed` is package-units, not a fixed dose; the
        -- unit-of-measure depends on the NDC's packaging.
        try_cast("Units Reimbursed" as double) as units_reimbursed,
        try_cast("Number of Prescriptions" as double) as number_of_prescriptions,
        try_cast("Total Amount Reimbursed" as double) as total_amount_reimbursed,
        try_cast("Medicaid Amount Reimbursed" as double) as medicaid_amount_reimbursed,
        try_cast("Non Medicaid Amount Reimbursed" as double) as non_medicaid_amount_reimbursed

    from source

)

select * from renamed
