-- =====================================================================
-- 05_features_t2d.sql  --  one feature row per cohort row
--
-- Every feature uses ONLY data from the 36 months up to and including
-- the index date. Nothing after the index date is allowed in here.
--
-- Feature groups
--   1. Labs & vitals: last, mean, min, max, slope/year, number of tests,
--      days since last test (HbA1c, glucose, BMI, BP, eGFR, creatinine)
--   2. Variability: SD of systolic BP and BMI
--   3. History: prediabetes / hypertension / CKD before index,
--      number of active conditions at index
--   4. Utilization: visits in 12 and 36 months, ED and inpatient visits,
--      days since last visit
--   5. Medications: number of active medications at index
--
-- Missing lab values are left as NULL on purpose: "never tested" carries
-- information. Missing-indicator columns are added in Python.
--
-- LEAKAGE WATCH: *_n_tests and *_days_since_last describe how doctors
-- behave, not the patient's biology. Query 6 of the sanity checks showed
-- HbA1c testing is ~7x higher in diabetic patients. Models must be
-- trained with and without these columns to measure their effect.
-- =====================================================================
\set ON_ERROR_STOP on

CREATE SCHEMA IF NOT EXISTS features;
DROP TABLE IF EXISTS features.t2d_v1;

CREATE TABLE features.t2d_v1 AS
WITH
-- 1. Labs and vitals inside the lookback window
obs AS (
    SELECT c.patient_id, c.index_date, r.concept_set, o.obs_ts, o.value
    FROM cohort.t2d_index c
    JOIN stg.observations o
      ON o.patient_id = c.patient_id
     AND o.obs_ts::date >  c.index_date - INTERVAL '36 months'
     AND o.obs_ts::date <= c.index_date
    JOIN ref.concept_set r
      ON r.code = o.loinc_code
     AND r.vocabulary = 'LOINC'
),
obs_agg AS (
    SELECT patient_id, index_date, concept_set,
           (ARRAY_AGG(value ORDER BY obs_ts DESC))[1]                AS last_val,
           AVG(value)                                                AS mean_val,
           MIN(value)                                                AS min_val,
           MAX(value)                                                AS max_val,
           STDDEV_SAMP(value)                                        AS sd_val,
           COUNT(*)                                                  AS n_obs,
           REGR_SLOPE(value, EXTRACT(EPOCH FROM obs_ts) / 31557600.0) AS slope_yr,
           index_date - MAX(obs_ts)::date                            AS days_since_last
    FROM obs
    GROUP BY patient_id, index_date, concept_set
),
obs_wide AS (
    SELECT patient_id, index_date,
        MAX(last_val)  FILTER (WHERE concept_set = 'hba1c') AS hba1c_last,
        MAX(mean_val)  FILTER (WHERE concept_set = 'hba1c') AS hba1c_mean,
        MAX(min_val)   FILTER (WHERE concept_set = 'hba1c') AS hba1c_min,
        MAX(max_val)   FILTER (WHERE concept_set = 'hba1c') AS hba1c_max,
        MAX(slope_yr)  FILTER (WHERE concept_set = 'hba1c') AS hba1c_slope_per_year,
        MAX(n_obs)     FILTER (WHERE concept_set = 'hba1c') AS hba1c_n_tests,
        MAX(days_since_last) FILTER (WHERE concept_set = 'hba1c') AS hba1c_days_since_last,
        MAX(last_val)  FILTER (WHERE concept_set = 'glucose') AS glucose_last,
        MAX(mean_val)  FILTER (WHERE concept_set = 'glucose') AS glucose_mean,
        MAX(min_val)   FILTER (WHERE concept_set = 'glucose') AS glucose_min,
        MAX(max_val)   FILTER (WHERE concept_set = 'glucose') AS glucose_max,
        MAX(slope_yr)  FILTER (WHERE concept_set = 'glucose') AS glucose_slope_per_year,
        MAX(n_obs)     FILTER (WHERE concept_set = 'glucose') AS glucose_n_tests,
        MAX(days_since_last) FILTER (WHERE concept_set = 'glucose') AS glucose_days_since_last,
        MAX(last_val)  FILTER (WHERE concept_set = 'bmi') AS bmi_last,
        MAX(mean_val)  FILTER (WHERE concept_set = 'bmi') AS bmi_mean,
        MAX(min_val)   FILTER (WHERE concept_set = 'bmi') AS bmi_min,
        MAX(max_val)   FILTER (WHERE concept_set = 'bmi') AS bmi_max,
        MAX(slope_yr)  FILTER (WHERE concept_set = 'bmi') AS bmi_slope_per_year,
        MAX(n_obs)     FILTER (WHERE concept_set = 'bmi') AS bmi_n_tests,
        MAX(days_since_last) FILTER (WHERE concept_set = 'bmi') AS bmi_days_since_last,
        MAX(last_val)  FILTER (WHERE concept_set = 'sbp') AS sbp_last,
        MAX(mean_val)  FILTER (WHERE concept_set = 'sbp') AS sbp_mean,
        MAX(min_val)   FILTER (WHERE concept_set = 'sbp') AS sbp_min,
        MAX(max_val)   FILTER (WHERE concept_set = 'sbp') AS sbp_max,
        MAX(slope_yr)  FILTER (WHERE concept_set = 'sbp') AS sbp_slope_per_year,
        MAX(n_obs)     FILTER (WHERE concept_set = 'sbp') AS sbp_n_tests,
        MAX(days_since_last) FILTER (WHERE concept_set = 'sbp') AS sbp_days_since_last,
        MAX(last_val)  FILTER (WHERE concept_set = 'dbp') AS dbp_last,
        MAX(mean_val)  FILTER (WHERE concept_set = 'dbp') AS dbp_mean,
        MAX(min_val)   FILTER (WHERE concept_set = 'dbp') AS dbp_min,
        MAX(max_val)   FILTER (WHERE concept_set = 'dbp') AS dbp_max,
        MAX(slope_yr)  FILTER (WHERE concept_set = 'dbp') AS dbp_slope_per_year,
        MAX(n_obs)     FILTER (WHERE concept_set = 'dbp') AS dbp_n_tests,
        MAX(days_since_last) FILTER (WHERE concept_set = 'dbp') AS dbp_days_since_last,
        MAX(last_val)  FILTER (WHERE concept_set = 'egfr') AS egfr_last,
        MAX(mean_val)  FILTER (WHERE concept_set = 'egfr') AS egfr_mean,
        MAX(min_val)   FILTER (WHERE concept_set = 'egfr') AS egfr_min,
        MAX(max_val)   FILTER (WHERE concept_set = 'egfr') AS egfr_max,
        MAX(slope_yr)  FILTER (WHERE concept_set = 'egfr') AS egfr_slope_per_year,
        MAX(n_obs)     FILTER (WHERE concept_set = 'egfr') AS egfr_n_tests,
        MAX(days_since_last) FILTER (WHERE concept_set = 'egfr') AS egfr_days_since_last,
        MAX(last_val)  FILTER (WHERE concept_set = 'creatinine') AS creatinine_last,
        MAX(mean_val)  FILTER (WHERE concept_set = 'creatinine') AS creatinine_mean,
        MAX(min_val)   FILTER (WHERE concept_set = 'creatinine') AS creatinine_min,
        MAX(max_val)   FILTER (WHERE concept_set = 'creatinine') AS creatinine_max,
        MAX(slope_yr)  FILTER (WHERE concept_set = 'creatinine') AS creatinine_slope_per_year,
        MAX(n_obs)     FILTER (WHERE concept_set = 'creatinine') AS creatinine_n_tests,
        MAX(days_since_last) FILTER (WHERE concept_set = 'creatinine') AS creatinine_days_since_last,
        MAX(sd_val)    FILTER (WHERE concept_set = 'sbp') AS sbp_sd,
        MAX(sd_val)    FILTER (WHERE concept_set = 'bmi') AS bmi_sd
    FROM obs_agg
    GROUP BY patient_id, index_date
),
-- 3. Diagnosis history before the index date
cond AS (
    SELECT c.patient_id, c.index_date,
           MAX(CASE WHEN r.concept_set = 'prediabetes'  THEN 1 ELSE 0 END) AS hx_prediabetes,
           MAX(CASE WHEN r.concept_set = 'hypertension' THEN 1 ELSE 0 END) AS hx_hypertension,
           MAX(CASE WHEN r.concept_set = 'ckd'          THEN 1 ELSE 0 END) AS hx_ckd,
           COUNT(DISTINCT s.condition_code)
               FILTER (WHERE s.resolved_date IS NULL
                          OR s.resolved_date > c.index_date)             AS n_active_conditions
    FROM cohort.t2d_index c
    JOIN stg.conditions s
      ON s.patient_id = c.patient_id
     AND s.onset_date <= c.index_date
    LEFT JOIN ref.concept_set r
      ON r.code = s.condition_code
     AND r.vocabulary = 'SNOMED'
    GROUP BY c.patient_id, c.index_date
),
-- 4. Healthcare utilization in the lookback window
enc AS (
    SELECT c.patient_id, c.index_date,
           COUNT(*) FILTER (WHERE e.start_ts::date > c.index_date - INTERVAL '12 months') AS n_visits_12m,
           COUNT(*)                                                                      AS n_visits_36m,
           COUNT(*) FILTER (WHERE e.encounter_class = 'emergency')                       AS n_ed_visits_36m,
           COUNT(*) FILTER (WHERE e.encounter_class = 'inpatient')                       AS n_inpatient_36m,
           c.index_date - MAX(e.start_ts)::date                                          AS days_since_last_visit
    FROM cohort.t2d_index c
    JOIN stg.encounters e
      ON e.patient_id = c.patient_id
     AND e.start_ts::date >  c.index_date - INTERVAL '36 months'
     AND e.start_ts::date <= c.index_date
    GROUP BY c.patient_id, c.index_date
),
-- 5. Medications active on the index date
meds AS (
    SELECT c.patient_id, c.index_date,
           COUNT(DISTINCT m.rxnorm_code) AS n_active_meds
    FROM cohort.t2d_index c
    JOIN stg.medications m
      ON m.patient_id = c.patient_id
     AND m.start_date <= c.index_date
     AND (m.stop_date IS NULL OR m.stop_date > c.index_date)
    GROUP BY c.patient_id, c.index_date
)
SELECT
    -- identifiers and label
    c.patient_id,
    c.index_date,
    c.label_t2d_24m,
    -- demographics (model features)
    c.age_at_index,
    CASE WHEN c.sex = 'F' THEN 1 ELSE 0 END    AS sex_female,
    -- demographics kept ONLY for the fairness audit, not as model inputs
    p.race                                     AS audit_race,
    p.ethnicity                                AS audit_ethnicity,
    -- labs and vitals
    w.hba1c_last,
    w.hba1c_mean,
    w.hba1c_min,
    w.hba1c_max,
    w.hba1c_slope_per_year,
    w.hba1c_n_tests,
    w.hba1c_days_since_last,
    w.glucose_last,
    w.glucose_mean,
    w.glucose_min,
    w.glucose_max,
    w.glucose_slope_per_year,
    w.glucose_n_tests,
    w.glucose_days_since_last,
    w.bmi_last,
    w.bmi_mean,
    w.bmi_min,
    w.bmi_max,
    w.bmi_slope_per_year,
    w.bmi_n_tests,
    w.bmi_days_since_last,
    w.sbp_last,
    w.sbp_mean,
    w.sbp_min,
    w.sbp_max,
    w.sbp_slope_per_year,
    w.sbp_n_tests,
    w.sbp_days_since_last,
    w.dbp_last,
    w.dbp_mean,
    w.dbp_min,
    w.dbp_max,
    w.dbp_slope_per_year,
    w.dbp_n_tests,
    w.dbp_days_since_last,
    w.egfr_last,
    w.egfr_mean,
    w.egfr_min,
    w.egfr_max,
    w.egfr_slope_per_year,
    w.egfr_n_tests,
    w.egfr_days_since_last,
    w.creatinine_last,
    w.creatinine_mean,
    w.creatinine_min,
    w.creatinine_max,
    w.creatinine_slope_per_year,
    w.creatinine_n_tests,
    w.creatinine_days_since_last,
    w.sbp_sd,
    w.bmi_sd,
    -- history
    COALESCE(h.hx_prediabetes, 0)      AS hx_prediabetes,
    COALESCE(h.hx_hypertension, 0)     AS hx_hypertension,
    COALESCE(h.hx_ckd, 0)              AS hx_ckd,
    COALESCE(h.n_active_conditions, 0) AS n_active_conditions,
    -- utilization
    COALESCE(e.n_visits_12m, 0)        AS n_visits_12m,
    COALESCE(e.n_visits_36m, 0)        AS n_visits_36m,
    COALESCE(e.n_ed_visits_36m, 0)     AS n_ed_visits_36m,
    COALESCE(e.n_inpatient_36m, 0)     AS n_inpatient_36m,
    e.days_since_last_visit,
    -- medications
    COALESCE(m.n_active_meds, 0)       AS n_active_meds
FROM cohort.t2d_index c
JOIN      stg.patients p USING (patient_id)
LEFT JOIN obs_wide     w ON w.patient_id = c.patient_id AND w.index_date = c.index_date
LEFT JOIN cond         h ON h.patient_id = c.patient_id AND h.index_date = c.index_date
LEFT JOIN enc          e ON e.patient_id = c.patient_id AND e.index_date = c.index_date
LEFT JOIN meds         m ON m.patient_id = c.patient_id AND m.index_date = c.index_date;

CREATE INDEX ON features.t2d_v1 (patient_id, index_date);
ANALYZE features.t2d_v1;

-- ---------------------------------------------------------------------
-- Check 1: one feature row per cohort row (the two counts must match)
-- ---------------------------------------------------------------------
SELECT (SELECT COUNT(*) FROM cohort.t2d_index) AS cohort_rows,
       (SELECT COUNT(*) FROM features.t2d_v1)  AS feature_rows;

-- ---------------------------------------------------------------------
-- Check 2: how often key labs are missing (percent of rows)
-- ---------------------------------------------------------------------
SELECT ROUND(100.0 * AVG((hba1c_last IS NULL)::int), 1) AS pct_missing_hba1c,
       ROUND(100.0 * AVG((glucose_last IS NULL)::int), 1) AS pct_missing_glucose,
       ROUND(100.0 * AVG((bmi_last   IS NULL)::int), 1) AS pct_missing_bmi,
       ROUND(100.0 * AVG((sbp_last   IS NULL)::int), 1) AS pct_missing_sbp,
       ROUND(100.0 * AVG((egfr_last  IS NULL)::int), 1) AS pct_missing_egfr
FROM features.t2d_v1;

-- ---------------------------------------------------------------------
-- Check 3: do features differ between future-diabetic and not?
-- (a first look at signal; not a model)
-- ---------------------------------------------------------------------
SELECT label_t2d_24m,
       COUNT(*)                          AS n_rows,
       ROUND(AVG(age_at_index), 1)       AS avg_age,
       ROUND(AVG(hba1c_last), 2)         AS avg_hba1c_last,
       ROUND(AVG(hba1c_slope_per_year)::numeric, 3) AS avg_hba1c_slope,
       ROUND(AVG(bmi_last), 1)           AS avg_bmi_last,
       ROUND(AVG(sbp_mean), 1)           AS avg_sbp_mean,
       ROUND(AVG(hx_prediabetes), 3)     AS share_prediabetes,
       ROUND(AVG(hba1c_n_tests), 2)      AS avg_hba1c_tests
FROM features.t2d_v1
GROUP BY label_t2d_24m
ORDER BY label_t2d_24m;
