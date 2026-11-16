"""Export features.t2d_v1 from Postgres to a Parquet file for modeling.

Adds missing-indicator columns for lab values ("never tested in the
lookback window" is itself informative in clinical data), then saves
data/processed/t2d_features_v1.parquet.

Usage:
    python pipelines/export_features.py
"""
import argparse
from pathlib import Path

import pandas as pd
from sqlalchemy import create_engine

DEFAULT_DSN = "postgresql+psycopg2://care:care@localhost:5432/chronic_care"
LABS = ["hba1c", "glucose", "bmi", "sbp", "dbp", "egfr", "creatinine"]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dsn", default=DEFAULT_DSN)
    parser.add_argument("--out", default="data/processed/t2d_features_v1.parquet")
    args = parser.parse_args()

    engine = create_engine(args.dsn)
    df = pd.read_sql("SELECT * FROM features.t2d_v1 ORDER BY patient_id, index_date", engine)

    # Postgres NUMERIC arrives as Python Decimal; convert everything numeric to float
    for col in df.columns:
        if col.startswith(tuple(LABS)) or col.startswith(("n_", "days_", "sbp_", "bmi_")):
            df[col] = pd.to_numeric(df[col], errors="coerce").astype("float64")
    df["index_date"] = pd.to_datetime(df["index_date"])

    # Missing indicators: 1 = this lab was never measured in the lookback window
    for lab in LABS:
        df[f"{lab}_missing"] = df[f"{lab}_last"].isna().astype("int8")

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    df.to_parquet(out, index=False)

    print(f"Saved {out}")
    print(f"  rows:              {len(df):,}")
    print(f"  patients:          {df['patient_id'].nunique():,}")
    print(f"  columns:           {df.shape[1]}")
    print(f"  positive rows:     {int(df['label_t2d_24m'].sum()):,} "
          f"({100 * df['label_t2d_24m'].mean():.2f}%)")
    print(f"  index years:       {df['index_date'].dt.year.min()} to {df['index_date'].dt.year.max()}")


if __name__ == "__main__":
    main()
