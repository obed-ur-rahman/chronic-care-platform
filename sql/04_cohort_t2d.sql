-- =====================================================================
-- 04_cohort_t2d.sql  --  type 2 diabetes prediction cohort
--
-- Prediction question:
--   For an adult (30-79) without diabetes on an index date, what is the
--   probability of a type 2 diabetes diagnosis within the next 24 months,
--   using only data from the prior 36 months?
--
-- Design:
--   * Index dates: July 1 of each year, 2010 onward (one row per
--     eligible patient per year). Rows from the same patient are
--     correlated, so train/test splits MUST be done by patient.
--   * Exclusions at index: already diagnosed with T2D, OR any prior
--     HbA1c >= 6.5% (undiagnosed diabetes), dead, outside age range,
--     or no encounter in the 36-month lookback (no data to learn from).
--   * Label: first T2D diagnosis in (index, index + 24 months].
--   * Follow-up: keep a row only if the patient had the event, or was
--     still observed at index + 24 months. Rows lost to follow-up are
--     dropped here; the survival models later will use them instead.
-- =====================================================================
\set ON_ERROR_STOP on

CREATE SCHEMA IF NOT EXISTS cohort;
DROP TABLE IF EXISTS cohort.t2d_index;

CREATE TABLE cohort.t2d_index AS
WITH params AS (
    SELECT INTERVAL '36 months' AS lookback,
           INTERVAL '24 months' AS horizon
),
data_end AS (
    SELECT MAX(start_ts)::date AS d FROM stg.encounters
),
index_dates AS (
    -- last index year leaves room for the full 24-month horizon
    SELECT make_date(y, 7, 1) AS index_date
    FROM generate_series(2010, (SELECT EXTRACT(YEAR FROM d)::int - 3 FROM data_end)) AS y
),
t2d_onset AS (
    SELECT c.patient_id, MIN(c.onset_date) AS onset_date
    FROM stg.conditions c
    JOIN ref.concept_set r ON r.code = c.condition_code AND r.concept_set = 't2d'
    GROUP BY c.patient_id
),
first_high_a1c AS (
    SELECT o.patient_id, MIN(o.obs_ts)::date AS high_date
    FROM stg.observations o
    JOIN ref.concept_set r ON r.code = o.loinc_code AND r.concept_set = 'hba1c'
    WHERE o.value >= 6.5
    GROUP BY o.patient_id
),
last_seen AS (
    SELECT patient_id, MAX(start_ts)::date AS last_date
    FROM stg.encounters
    GROUP BY patient_id
),
candidates AS (
    SELECT p.patient_id, p.sex, p.death_date, i.index_date,
           EXTRACT(YEAR FROM age(i.index_date, p.birth_date))::int AS age_at_index
    FROM stg.patients p
    CROSS JOIN index_dates i
    WHERE p.birth_date < i.index_date
)
SELECT
    c.patient_id,
    c.index_date,
    c.age_at_index,
    c.sex,
    t.onset_date AS t2d_onset_date,
    CASE WHEN t.onset_date >  c.index_date
          AND t.onset_date <= c.index_date + (SELECT horizon FROM params)
         THEN 1 ELSE 0 END AS label_t2d_24m
FROM candidates c
JOIN      last_seen      ls USING (patient_id)
LEFT JOIN t2d_onset      t  USING (patient_id)
LEFT JOIN first_high_a1c h  USING (patient_id)
WHERE c.age_at_index BETWEEN 30 AND 79
  -- alive at index
  AND (c.death_date IS NULL OR c.death_date > c.index_date)
  -- no diabetes yet, diagnosed or undiagnosed
  AND (t.onset_date IS NULL OR t.onset_date > c.index_date)
  AND (h.high_date  IS NULL OR h.high_date  > c.index_date)
  -- has data in the lookback window
  AND EXISTS (
        SELECT 1 FROM stg.encounters e
        WHERE e.patient_id = c.patient_id
          AND e.start_ts::date >  c.index_date - (SELECT lookback FROM params)
          AND e.start_ts::date <= c.index_date
      )
  -- observed long enough to know the label
  AND (
        (t.onset_date > c.index_date
         AND t.onset_date <= c.index_date + (SELECT horizon FROM params))
        OR ls.last_date >= c.index_date + (SELECT horizon FROM params)
      );

CREATE INDEX ON cohort.t2d_index (patient_id, index_date);
ANALYZE cohort.t2d_index;

-- ---------------------------------------------------------------------
-- Summary 1: overall size and positive rate
-- ---------------------------------------------------------------------
SELECT COUNT(*)                                AS n_rows,
       COUNT(DISTINCT patient_id)              AS n_patients,
       SUM(label_t2d_24m)                      AS n_positive_rows,
       COUNT(DISTINCT patient_id) FILTER (WHERE label_t2d_24m = 1) AS n_positive_patients,
       ROUND(100.0 * AVG(label_t2d_24m), 2)    AS pct_positive
FROM cohort.t2d_index;

-- ---------------------------------------------------------------------
-- Summary 2: rows and positives by index year (for the temporal split)
-- ---------------------------------------------------------------------
SELECT EXTRACT(YEAR FROM index_date)::int AS index_year,
       COUNT(*)                           AS n_rows,
       SUM(label_t2d_24m)                 AS n_positive
FROM cohort.t2d_index
GROUP BY 1
ORDER BY 1;
