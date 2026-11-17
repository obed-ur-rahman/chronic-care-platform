"""Train the first T2D risk models and evaluate them honestly.

Split design (no leakage across people or time):
  * Patients are split 80/20 into train and test groups, so no person
    appears on both sides.
  * Train uses index years up to TRAIN_END_YEAR; test uses index years
    from TEST_START_YEAR on. The gap year keeps the 24-month label window
    of the last training rows from overlapping the test period.

Two feature sets are compared:
  * all            every feature
  * no_utilization drops features that describe how often doctors ordered
                   tests or saw the patient (*_n_tests, *_days_since_last,
                   *_missing, visit counts). The gap between the two shows
                   how much the model relies on care patterns vs biology.

Models:
  * Logistic regression (baseline; must be beaten to justify complexity)
  * LightGBM (gradient boosting; handles missing values natively)

Metrics: AUROC, AUPRC (better for rare outcomes), Brier score (calibration).

Usage:
    python models/train_baseline.py
"""
import argparse
from pathlib import Path

import lightgbm as lgb
import numpy as np
import pandas as pd
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import average_precision_score, brier_score_loss, roc_auc_score
from sklearn.model_selection import GroupShuffleSplit
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler

LABEL = "label_t2d_24m"
NON_FEATURES = {"patient_id", "index_date", LABEL, "audit_race", "audit_ethnicity"}
TRAIN_END_YEAR = 2017
TEST_START_YEAR = 2019
SEED = 42


def is_utilization(col: str) -> bool:
    return (
        col.endswith(("_n_tests", "_days_since_last", "_missing"))
        or col.startswith("n_visits")
        or col == "days_since_last_visit"
    )


def split(df: pd.DataFrame):
    gss = GroupShuffleSplit(n_splits=1, test_size=0.2, random_state=SEED)
    train_idx, test_idx = next(gss.split(df, groups=df["patient_id"]))
    years = df["index_date"].dt.year
    train = df.iloc[train_idx][years.iloc[train_idx] <= TRAIN_END_YEAR]
    test = df.iloc[test_idx][years.iloc[test_idx] >= TEST_START_YEAR]
    assert not set(train["patient_id"]) & set(test["patient_id"]), "patient leak"
    return train, test


def build_models(pos_rate: float):
    logreg = make_pipeline(
        SimpleImputer(strategy="median", add_indicator=False),
        StandardScaler(),
        LogisticRegression(C=0.1, max_iter=2000),
    )
    lgbm = lgb.LGBMClassifier(
        n_estimators=300,
        learning_rate=0.03,
        num_leaves=15,
        min_child_samples=20,
        subsample=0.8,
        subsample_freq=1,
        colsample_bytree=0.8,
        reg_lambda=1.0,
        random_state=SEED,
        verbose=-1,
    )
    return {"logistic_regression": logreg, "lightgbm": lgbm}


def evaluate(y, p) -> dict:
    if y.nunique() < 2:
        return {"auroc": np.nan, "auprc": np.nan, "brier": brier_score_loss(y, p)}
    return {
        "auroc": roc_auc_score(y, p),
        "auprc": average_precision_score(y, p),
        "brier": brier_score_loss(y, p),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--features", default="data/processed/t2d_features_v1.parquet")
    parser.add_argument("--out", default="reports/baseline_results.csv")
    args = parser.parse_args()

    df = pd.read_parquet(args.features)
    df["index_date"] = pd.to_datetime(df["index_date"])
    train, test = split(df)

    print(f"Train: {len(train):,} rows, {train['patient_id'].nunique():,} patients, "
          f"{int(train[LABEL].sum())} positives, years <= {TRAIN_END_YEAR}")
    print(f"Test:  {len(test):,} rows, {test['patient_id'].nunique():,} patients, "
          f"{int(test[LABEL].sum())} positives, years >= {TEST_START_YEAR}")
    if test[LABEL].sum() < 20:
        print("WARNING: fewer than 20 test positives; metrics will be unstable.")

    all_feats = [c for c in df.columns if c not in NON_FEATURES]
    feature_sets = {
        "all": all_feats,
        "no_utilization": [c for c in all_feats if not is_utilization(c)],
    }

    rows = []
    for fs_name, feats in feature_sets.items():
        for model_name, model in build_models(train[LABEL].mean()).items():
            model.fit(train[feats], train[LABEL])
            p = model.predict_proba(test[feats])[:, 1]
            rows.append({"feature_set": fs_name, "n_features": len(feats),
                         "model": model_name, **evaluate(test[LABEL], p)})

    results = pd.DataFrame(rows)
    results["prevalence"] = test[LABEL].mean()
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    results.to_csv(out, index=False)

    print()
    print(results.round(4).to_string(index=False))
    print(f"\nAUPRC of a random guess = prevalence = {test[LABEL].mean():.4f}")
    print(f"Saved {out}")


if __name__ == "__main__":
    main()
