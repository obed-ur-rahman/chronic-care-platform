-- =====================================================================
-- 01_sanity_checks.sql  --  run after load_synthea.py
-- Goal: understand what Synthea generated BEFORE defining any cohort.
-- =====================================================================

-- 1. Patient overview
SELECT COUNT(*)                                        AS n_patients,
       COUNT(*) FILTER (WHERE NULLIF(deathdate, '') IS NULL) AS alive,
       MIN(birthdate::date)                            AS oldest_birth,
       MAX(birthdate::date)                            AS youngest_birth
FROM raw.patients;

-- 2. Discover the exact condition codes Synthea uses for our diseases.
--    Copy the codes you need into a config file; never hardcode from memory.
SELECT code, description, COUNT(DISTINCT patient) AS n_patients
FROM raw.conditions
WHERE description ILIKE ANY (ARRAY['%diabetes%', '%prediabetes%',
                                   '%hypertension%', '%kidney%'])
GROUP BY code, description
ORDER BY n_patients DESC;

-- 3. Discover the lab / vital codes (LOINC) and their units.
SELECT code, description, units,
       COUNT(*)                AS n_obs,
       COUNT(DISTINCT patient) AS n_patients
FROM raw.observations
WHERE description ILIKE ANY (ARRAY['%a1c%', '%glucose%', '%glomerular%',
                                   '%systolic%', '%diastolic%', '%body mass%',
                                   '%cholesterol%', '%creatinine%'])
GROUP BY code, description, units
ORDER BY n_patients DESC;

-- 4. Longitudinal depth: how many years of encounters per patient?
SELECT percentile_cont(ARRAY[0.1, 0.5, 0.9])
       WITHIN GROUP (ORDER BY span_years) AS p10_p50_p90_years
FROM (
    SELECT patient,
           ((MAX(start::timestamptz)::date - MIN(start::timestamptz)::date) / 365.25)::float AS span_years
    FROM raw.encounters
    GROUP BY patient
) t;

-- 5. Age at first type 2 diabetes diagnosis (is incidence realistic?)
--    Replace the ILIKE filter with exact codes from query 2 once known.
WITH first_dx AS (
    SELECT patient, MIN(start::date) AS dx_date
    FROM raw.conditions
    WHERE description ILIKE '%diabetes%'
      AND description NOT ILIKE '%prediabetes%'
    GROUP BY patient
)
SELECT (FLOOR(EXTRACT(YEAR FROM age(f.dx_date, p.birthdate::date)) / 10) * 10)::int AS age_band,
       COUNT(*) AS n_new_diagnoses
FROM first_dx f
JOIN raw.patients p ON p.id = f.patient
GROUP BY age_band
ORDER BY age_band;

-- 6. LEAKAGE CHECK: are HbA1c tests mostly ordered for people who already
--    have diabetes? If yes, "has an HbA1c test" is a proxy for the label.
WITH dm AS (
    SELECT DISTINCT patient
    FROM raw.conditions
    WHERE description ILIKE '%diabetes%'
      AND description NOT ILIKE '%prediabetes%'
)
SELECT CASE WHEN dm.patient IS NULL THEN 'no diabetes' ELSE 'diabetes' END AS grp,
       COUNT(DISTINCT p.id)                                 AS n_patients,
       ROUND(COUNT(o.patient)::numeric / COUNT(DISTINCT p.id), 2) AS a1c_tests_per_patient
FROM raw.patients p
LEFT JOIN dm             ON dm.patient = p.id
LEFT JOIN raw.observations o
       ON o.patient = p.id AND o.description ILIKE '%a1c%'
GROUP BY 1;
