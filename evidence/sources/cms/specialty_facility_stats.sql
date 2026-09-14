-- Headline aggregates across all three specialty-facility marts.
-- Every field is a scalar so the page can `<Value>` it directly.
select
    (
        select count(*) from main_marts.dim_dialysis_facility
    ) as dialysis_facilities,
    (
        select count(distinct state) from main_marts.dim_dialysis_facility
    ) as dialysis_states,
    (
        select sum(case when is_for_profit then 1 else 0 end)
        from main_marts.dim_dialysis_facility
    ) as dialysis_for_profit,
    (
        select sum(case when is_chain_owned then 1 else 0 end)
        from main_marts.dim_dialysis_facility
    ) as dialysis_chain_owned,
    (
        select sum(number_of_dialysis_stations)
        from main_marts.dim_dialysis_facility
    ) as dialysis_stations,
    (
        select count(five_star) from main_marts.dim_dialysis_facility
    ) as dialysis_rated,
    (
        select avg(five_star::double) from main_marts.dim_dialysis_facility
    ) as dialysis_avg_stars,
    (
        select max(as_of) from main_marts.dim_dialysis_facility
    ) as dialysis_as_of,
    (
        select count(*) from main_marts.dim_irf
    ) as irf_facilities,
    (
        select count(distinct state) from main_marts.dim_irf
    ) as irf_states,
    (
        select sum(case when facility_type = 'Freestanding' then 1 else 0 end)
        from main_marts.dim_irf
    ) as irf_freestanding,
    (
        select sum(case when facility_type = 'Hospital unit' then 1 else 0 end)
        from main_marts.dim_irf
    ) as irf_hospital_units,
    (
        select max(as_of) from main_marts.dim_irf
    ) as irf_as_of,
    (
        select count(*) from main_marts.dim_ltch
    ) as ltch_facilities,
    (
        select count(distinct state) from main_marts.dim_ltch
    ) as ltch_states,
    (
        select count(total_number_of_beds) from main_marts.dim_ltch
    ) as ltch_with_bed_count,
    (
        select sum(total_number_of_beds) from main_marts.dim_ltch
    ) as ltch_total_beds,
    (
        select avg(total_number_of_beds::double)
        from main_marts.dim_ltch
    ) as ltch_avg_beds,
    (
        select max(as_of) from main_marts.dim_ltch
    ) as ltch_as_of,
    (
        select count(*) from main_marts.fct_dialysis_quality
    ) as dialysis_quality_rows,
    (
        select count(distinct measure_code)
        from main_marts.fct_dialysis_quality
    ) as dialysis_quality_measures,
    (
        select max(as_of) from main_marts.fct_dialysis_quality
    ) as dialysis_quality_as_of
