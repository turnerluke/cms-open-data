with source as (

    select * from {{ source('cms_vintages', 'dataset_vintages') }}

),

renamed as (

    select
        -- identity
        dataset_key,
        source_family,
        dataset_id,

        -- upstream publication dates (as CMS reported them at capture)
        modified,
        issued,
        released,
        temporal_start,
        temporal_end,

        -- local capture timestamp (UTC)
        captured_at

    from source

)

select * from renamed
