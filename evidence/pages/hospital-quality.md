---
title: Hospital quality
---

Quality of Medicare-certified hospitals from CMS Care Compare: the
overall star rating from `dim_hospital`, and healthcare-associated
infection (HAI) results from `fct_hospital_quality`. Quality scores are
only comparable **within** a measure, so each view below is filtered to
specific `measure_id`s and never aggregates across measures.

## Overall star ratings

```sql rating_coverage
select
    count(*) as total_hospitals,
    count(hospital_overall_rating) as rated_hospitals,
    count(hospital_overall_rating) / cast(count(*) as double) as rated_share,
    avg(hospital_overall_rating) as avg_rating
from cms.dim_hospital
```

<BigValue data={rating_coverage} value=total_hospitals title="Hospitals" fmt=num0 />
<BigValue data={rating_coverage} value=rated_share title="With a star rating" fmt=pct1 />
<BigValue data={rating_coverage} value=avg_rating title="Average stars" fmt=num2 />

```sql star_distribution
select
    hospital_overall_rating as stars,
    count(*) as hospitals
from cms.dim_hospital
where hospital_overall_rating is not null
group by 1
order by 1
```

<BarChart
  data={star_distribution}
  x=stars
  y=hospitals
  title="Hospitals by overall star rating"
/>

## Healthcare-associated infections

Standardized infection ratios (SIR): below 1.0 means fewer infections
than the national baseline predicts, above 1.0 means more. Each SIR
measure is summarized separately. Averages are unweighted means across
reporting hospitals — small and large facilities count equally.

```sql infection_sir
select
    measure_id,
    any_value(measure_name) as measure_name,
    count(score) as hospitals_reporting,
    avg(score) as avg_sir,
    count(case when compared_to_national ilike 'better%' then 1 end)
        as better_than_national,
    count(case when compared_to_national ilike 'worse%' then 1 end)
        as worse_than_national
from cms.hospital_quality
where
    measure_domain = 'infections'
    and measure_id in (
        'HAI_1_SIR', 'HAI_2_SIR', 'HAI_3_SIR',
        'HAI_4_SIR', 'HAI_5_SIR', 'HAI_6_SIR'
    )
group by 1
order by 1
```

<BarChart
  data={infection_sir}
  x=measure_id
  y=avg_sir
  swapXY=true
  title="Average (unweighted) SIR by infection measure (1.0 = national baseline)"
  yFmt=num2
>
  <ReferenceLine y=1 label="National baseline" />
</BarChart>

<DataTable data={infection_sir}>
  <Column id=measure_id title="Measure" />
  <Column id=measure_name title="Description" wrap=true />
  <Column id=hospitals_reporting title="Reporting" fmt=num0 />
  <Column id=avg_sir title="Avg SIR" fmt=num2 />
  <Column id=better_than_national title="Better than national" fmt=num0 />
  <Column id=worse_than_national title="Worse than national" fmt=num0 />
</DataTable>
