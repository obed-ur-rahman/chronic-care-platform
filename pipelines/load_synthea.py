"""Load Synthea CSV exports into PostgreSQL (schema: raw).

Every column is loaded as TEXT so this works across Synthea versions
(column sets change between releases). Typing and cleaning happen later
in SQL, in a separate staging layer -- the standard raw -> staging -> features
pattern.

Usage:
    python pipelines/load_synthea.py --csv-dir data/raw/synthea/csv
"""
import argparse
import csv
import time
from pathlib import Path

import psycopg2
from psycopg2 import sql

DEFAULT_DSN = "postgresql://care:care@localhost:5432/chronic_care"


def load_file(cur, conn, path: Path) -> int:
    table = path.stem.lower()
    with path.open(newline="", encoding="utf-8") as fh:
        header = next(csv.reader(fh))
    cols = [h.strip().lower() for h in header]

    cur.execute(sql.SQL("DROP TABLE IF EXISTS raw.{};").format(sql.Identifier(table)))
    cur.execute(
        sql.SQL("CREATE TABLE raw.{} ({});").format(
            sql.Identifier(table),
            sql.SQL(", ").join(sql.SQL("{} TEXT").format(sql.Identifier(c)) for c in cols),
        )
    )
    copy_stmt = sql.SQL("COPY raw.{} FROM STDIN WITH (FORMAT csv, HEADER true)").format(
        sql.Identifier(table)
    )
    with path.open("r", encoding="utf-8") as fh:
        cur.copy_expert(copy_stmt.as_string(conn), fh)

    cur.execute(sql.SQL("SELECT COUNT(*) FROM raw.{};").format(sql.Identifier(table)))
    return cur.fetchone()[0]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--csv-dir", default="data/raw/synthea/csv")
    parser.add_argument("--dsn", default=DEFAULT_DSN)
    args = parser.parse_args()

    csv_dir = Path(args.csv_dir)
    files = sorted(csv_dir.glob("*.csv"))
    if not files:
        raise SystemExit(f"No CSV files found in {csv_dir.resolve()}")

    conn = psycopg2.connect(args.dsn)
    try:
        with conn.cursor() as cur:
            cur.execute("CREATE SCHEMA IF NOT EXISTS raw;")
            conn.commit()
            for f in files:
                t0 = time.time()
                n = load_file(cur, conn, f)
                conn.commit()
                print(f"raw.{f.stem.lower():<22} {n:>12,} rows  ({time.time() - t0:.1f}s)")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
