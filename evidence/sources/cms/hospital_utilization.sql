select
    ccn,
    inpatient_total_discharges,
    inpatient_total_medicare_payment_amount,
    inpatient_medicare_payment_per_discharge,
    inpatient_avg_length_of_stay,
    inpatient_avg_hcc_risk_score,
    as_of
from main_marts.fct_hospital_utilization
