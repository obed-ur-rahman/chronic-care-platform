-- =====================================================================
-- 02_staging.sql  --  raw (all TEXT) -> stg (typed, cleaned)
-- Re-runnable: drops and rebuilds the stg schema each time.
-- Direct identifiers (SSN, passport, names, address) are deliberately
-- NOT carried into staging, even though the data is synthetic.
-- =====================================================================
\set ON_ERROR_STOP on

DROP SCHEMA IF EXISTS stg CASCADE;
CREATE SCHEMA stg;

-- ---------------------------------------------------------------------
-- Patients: demographics only
-- ---------------------------------------------------------------------
CREATE TABLE stg.patients AS
SELECT
    id                                   AS patient_id,
    birthdate::date                      AS birth_date,
    NULLIF(deathdate, '')::date          AS death_date,
    UPPER(gender)                        AS sex,
    LOWER(race)                          AS race,
    LOWER(ethnicity)                     AS ethnicity,
    marital                              AS marital_status,
    county,
    state
FROM raw.patients;

ALTER TABLE stg.patients ADD PRIMARY KEY (patient_id);

-- ---------------------------------------------------------------------
-- Encounters: visits (used for utilization features + history span)
-- ---------------------------------------------------------------------
CREATE TABLE stg.encounters AS
SELECT
    id                                        AS encounter_id,
    patient                                   AS patient_id,
    start::timestamptz                        AS start_ts,
    NULLIF(stop, '')::timestamptz             AS stop_ts,
    LOWER(encounterclass)                     AS encounter_class,
    code                                      AS encounter_code,
    description                               AS encounter_description,
    NULLIF(reasoncode, '')                    AS reason_code,
    NULLIF(reasondescription, '')             AS reason_description
FROM raw.encounters;

-- ---------------------------------------------------------------------
-- Conditions: diagnoses with onset (and resolution) dates
-- ---------------------------------------------------------------------
CREATE TABLE stg.conditions AS
SELECT
    patient                                   AS patient_id,
    NULLIF(encounter, '')                     AS encounter_id,
    start::timestamptz::date                  AS onset_date,
    NULLIF(stop, '')::timestamptz::date       AS resolved_date,
    code                                      AS condition_code,
    description                               AS condition_description
FROM raw.conditions;

-- ---------------------------------------------------------------------
-- Observations: numeric labs and vitals only
-- (text observations like survey answers are excluded for now)
-- ---------------------------------------------------------------------
CREATE TABLE stg.observations AS
SELECT
    patient                                   AS patient_id,
    NULLIF(encounter, '')                     AS encounter_id,
    date::timestamptz                         AS obs_ts,
    LOWER(category)                           AS category,
    code                                      AS loinc_code,
    description                               AS obs_description,
    value::numeric                            AS value,
    units
FROM raw.observations
WHERE LOWER(type) = 'numeric'
  AND value ~ '^-?[0-9]+(\.[0-9]+)?$';

-- ---------------------------------------------------------------------
-- Medications: prescriptions with start/stop
-- ---------------------------------------------------------------------
CREATE TABLE stg.medications AS
SELECT
    patient                                   AS patient_id,
    NULLIF(encounter, '')                     AS encounter_id,
    start::timestamptz::date                  AS start_date,
    NULLIF(stop, '')::timestamptz::date       AS stop_date,
    code                                      AS rxnorm_code,
    description                               AS medication_description,
    NULLIF(reasoncode, '')                    AS reason_code,
    NULLIF(reasondescription, '')             AS reason_description
FROM raw.medications;

-- ---------------------------------------------------------------------
-- Indexes for the joins and time filters used in cohort building
-- ---------------------------------------------------------------------
CREATE INDEX ON stg.encounters   (patient_id, start_ts);
CREATE INDEX ON stg.conditions   (patient_id, onset_date);
CREATE INDEX ON stg.conditions   (condition_code);
CREATE INDEX ON stg.observations (patient_id, loinc_code, obs_ts);
CREATE INDEX ON stg.medications  (patient_id, start_date);

ANALYZE stg.patients;
ANALYZE stg.encounters;
ANALYZE stg.conditions;
ANALYZE stg.observations;
ANALYZE stg.medications;

-- ---------------------------------------------------------------------
-- Verification: row counts raw vs stg
-- ---------------------------------------------------------------------
SELECT 'patients'     AS tbl, (SELECT COUNT(*) FROM raw.patients)     AS raw_rows, (SELECT COUNT(*) FROM stg.patients)     AS stg_rows
UNION ALL
SELECT 'encounters',          (SELECT COUNT(*) FROM raw.encounters),            (SELECT COUNT(*) FROM stg.encounters)
UNION ALL
SELECT 'conditions',          (SELECT COUNT(*) FROM raw.conditions),            (SELECT COUNT(*) FROM stg.conditions)
UNION ALL
SELECT 'observations',        (SELECT COUNT(*) FROM raw.observations),          (SELECT COUNT(*) FROM stg.observations)
UNION ALL
SELECT 'medications',         (SELECT COUNT(*) FROM raw.medications),           (SELECT COUNT(*) FROM stg.medications);
