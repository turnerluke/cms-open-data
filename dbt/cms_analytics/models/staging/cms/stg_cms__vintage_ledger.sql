with source as (

    select * from {{ source('cms_vintage_ledger', 'vintage_ledger') }}

),

renamed as (

    select
        -- ledger identity
        ledger_version,
        run_date,
        captured_at,

        -- dataset identity
        asset_name,
        dataset_key,
        source_family,
        dataset_id,

        -- upstream publication dates carried through from the sidecar
        modified,
        issued,
        released,
        temporal_start,
        temporal_end,

        -- local dataset summary (from Parquet footers, at capture time)
        row_count,
        file_count,
        total_bytes,
        schema_hash

    from source

)

select * from renamed
