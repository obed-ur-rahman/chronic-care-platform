# Chronic Care Platform

AI-powered chronic disease risk prediction and longitudinal care management,
built on synthetic patient data generated with Synthea.

**Status:** Phase 1, data generation and loading.

## Quick start
1. Generate patients with Synthea (see `docs/` once written).
2. `docker compose up -d`
3. `pip install -r requirements.txt`
4. `python pipelines/load_synthea.py --csv-dir data/raw/synthea/csv`
5. Run `sql/01_sanity_checks.sql`

> Synthetic data only. Not a medical device and not for clinical use.
