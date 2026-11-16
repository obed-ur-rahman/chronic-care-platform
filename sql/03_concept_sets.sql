-- =====================================================================
-- 03_concept_sets.sql  --  the ONE place clinical codes are defined.
-- Every later query joins to ref.concept_set instead of hardcoding codes
-- or searching descriptions with ILIKE.
-- Codes are Synthea's standard SNOMED (diagnoses) and LOINC (labs/vitals).
-- The verification query at the bottom confirms each exists in YOUR data.
-- =====================================================================
\set ON_ERROR_STOP on

CREATE SCHEMA IF NOT EXISTS ref;
DROP TABLE IF EXISTS ref.concept_set;

CREATE TABLE ref.concept_set (
    concept_set TEXT NOT NULL,   -- logical group used in queries
    vocabulary  TEXT NOT NULL,   -- SNOMED or LOINC
    code        TEXT NOT NULL,
    note        TEXT
);

INSERT INTO ref.concept_set (concept_set, vocabulary, code, note) VALUES
    -- Diagnoses (SNOMED)
    ('t2d',          'SNOMED', '44054006',  'Diabetes mellitus type 2'),
    ('prediabetes',  'SNOMED', '714628002', 'Prediabetes (Synthea code)'),
    ('hypertension', 'SNOMED', '59621000',  'Essential hypertension'),
    ('ckd',          'SNOMED', '431855005', 'Chronic kidney disease stage 1'),
    ('ckd',          'SNOMED', '431856006', 'Chronic kidney disease stage 2'),
    ('ckd',          'SNOMED', '433144002', 'Chronic kidney disease stage 3'),
    ('ckd',          'SNOMED', '431857002', 'Chronic kidney disease stage 4'),
    ('ckd',          'SNOMED', '46177005',  'End-stage renal disease'),
    -- Labs and vitals (LOINC)
    ('hba1c',        'LOINC',  '4548-4',    'Hemoglobin A1c'),
    ('glucose',      'LOINC',  '2339-0',    'Glucose'),
    ('bmi',          'LOINC',  '39156-5',   'Body mass index'),
    ('sbp',          'LOINC',  '8480-6',    'Systolic blood pressure'),
    ('dbp',          'LOINC',  '8462-4',    'Diastolic blood pressure'),
    ('egfr',         'LOINC',  '33914-3',   'eGFR'),
    ('creatinine',   'LOINC',  '38483-4',   'Creatinine');

-- ---------------------------------------------------------------------
-- Check 1: does every code exist in this dataset?
-- n_patients = 0 means your Synthea version uses a different code.
-- ---------------------------------------------------------------------
SELECT r.concept_set, r.vocabulary, r.code, r.note,
       COALESCE(cond.n, obs.n, 0) AS n_patients
FROM ref.concept_set r
LEFT JOIN (SELECT condition_code AS code, COUNT(DISTINCT patient_id) AS n
           FROM stg.conditions GROUP BY 1) cond
       ON r.vocabulary = 'SNOMED' AND cond.code = r.code
LEFT JOIN (SELECT loinc_code AS code, COUNT(DISTINCT patient_id) AS n
           FROM stg.observations GROUP BY 1) obs
       ON r.vocabulary = 'LOINC' AND obs.code = r.code
ORDER BY r.concept_set, r.code;

-- ---------------------------------------------------------------------
-- Check 2: related diagnoses in the data that are NOT in our sets.
-- Review these; add any that belong (e.g. a different T2D code).
-- ---------------------------------------------------------------------
SELECT condition_code, condition_description,
       COUNT(DISTINCT patient_id) AS n_patients
FROM stg.conditions
WHERE condition_description ILIKE ANY (ARRAY['%diabetes%', '%hypertension%', '%kidney%'])
  AND condition_code NOT IN (SELECT code FROM ref.concept_set)
GROUP BY 1, 2
ORDER BY n_patients DESC;
