with source as (

    select * from {{ source('cms_raw', 'cms_home_health_national') }}

),

renamed as (

    select
        -- one-row national benchmark. `country` is always `Nation` in
        -- the current vintage; kept for provenance.
        trim(country) as country,

        -- overall star-rating distribution (percent of agencies at
        -- each rating band, 0.5-star increments)
        try_cast(quality_of_patient_care_star_rating as double) as quality_of_patient_care_star_rating,
        try_cast(star_rating_1_percentage as double) as star_rating_1_pct,
        try_cast(star_rating_15_percentage as double) as star_rating_1_5_pct,
        try_cast(star_rating_2_percentage as double) as star_rating_2_pct,
        try_cast(star_rating_25_percentage as double) as star_rating_2_5_pct,
        try_cast(star_rating_3_percentage as double) as star_rating_3_pct,
        try_cast(star_rating_35_percentage as double) as star_rating_3_5_pct,
        try_cast(star_rating_4_percentage as double) as star_rating_4_pct,
        try_cast(star_rating_45_percentage as double) as star_rating_4_5_pct,
        try_cast(star_rating_5_percentage as double) as star_rating_5_pct,

        -- OASIS process/outcome national rates (percentages)
        try_cast(how_often_the_home_health_team_began_their_patients_care_in_d440 as double)
            as timely_initiation_rate,
        try_cast(how_often_the_home_health_team_determined_whether_patients__4505 as double)
            as drug_education_rate,
        try_cast(how_often_patients_got_better_at_walking_or_moving_around as double)
            as improve_ambulation_rate,
        try_cast(how_often_patients_got_better_at_getting_in_and_out_of_bed as double)
            as improve_bed_transferring_rate,
        try_cast(how_often_patients_got_better_at_bathing as double) as improve_bathing_rate,
        try_cast(how_often_patients_breathing_improved as double) as improve_breathing_rate,
        try_cast(how_often_patients_got_better_at_taking_their_drugs_correct_bd88 as double)
            as improve_drug_taking_rate,
        try_cast(changes_in_skin_integrity_postacute_care_pressure_ulcerinjury as double)
            as pressure_ulcer_rate,
        try_cast(how_often_physicianrecommended_actions_to_address_medicatio_cc88 as double)
            as medication_action_rate,
        try_cast(percent_of_residents_experiencing_one_or_more_falls_with_ma_34b8 as double)
            as major_falls_rate,
        try_cast(discharge_function_score as double) as discharge_function_rate,
        try_cast(transfer_of_health_information_to_the_provider as double) as transfer_hi_provider_rate,
        try_cast(transfer_of_health_information_to_the_patient as double) as transfer_hi_patient_rate,

        -- national performance-category counts for the three claims-
        -- based measures (PPR, DTC, PPH); each row here is a national
        -- rollup, not an agency count
        try_cast(ppr_number_of_hhas_that_performed_better_than_the_national__ad82 as int)
            as ppr_agencies_better_than_national,
        try_cast(ppr_number_of_hhas_that_performed_no_different_than_the_nat_a986 as int)
            as ppr_agencies_no_different_than_national,
        try_cast(ppr_number_of_hhas_that_performed_worse_than_the_national_o_f73a as int)
            as ppr_agencies_worse_than_national,
        try_cast(ppr_number_of_hhas_that_have_too_few_cases_for_public_reporting as int)
            as ppr_agencies_too_few_cases,
        try_cast(ppr_national_observed_rate as double) as ppr_national_observed_rate,

        try_cast(dtc_number_of_hhas_that_performed_better_than_the_national__64e2 as int)
            as dtc_agencies_better_than_national,
        try_cast(dtc_number_of_hhas_that_performed_no_different_than_the_nat_f19f as int)
            as dtc_agencies_no_different_than_national,
        try_cast(dtc_number_of_hhas_that_performed_worse_than_the_national_o_9aa2 as int)
            as dtc_agencies_worse_than_national,
        try_cast(dtc_number_of_hhas_that_have_too_few_cases_for_public_reporting as int)
            as dtc_agencies_too_few_cases,
        try_cast(dtc_national_observed_rate as double) as dtc_national_observed_rate,

        try_cast(pph_number_of_hhas_that_performed_better_than_the_national__9c83 as int)
            as pph_agencies_better_than_national,
        try_cast(pph_number_of_hhas_that_performed_no_different_than_the_nat_93f5 as int)
            as pph_agencies_no_different_than_national,
        try_cast(pph_number_of_hhas_that_performed_worse_than_the_national_o_1890 as int)
            as pph_agencies_worse_than_national,
        try_cast(pph_number_of_hhas_that_have_too_few_cases_for_public_reporting as int)
            as pph_agencies_too_few_cases,
        try_cast(pph_national_observed_rate as double) as pph_national_observed_rate,

        try_cast(how_much_medicare_spends_on_an_episode_of_care_at_this_agen_56e6 as double)
            as medicare_spending_per_episode

    from source

)

select * from renamed
