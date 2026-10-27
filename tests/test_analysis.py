"""Unit tests for the statistical helpers, on small synthetic data."""

import numpy as np
import pandas as pd
import pytest

from src.analysis import delivered_with_review, late_delivery_tests, negative_review_model


def _orders(n_on_time=200, n_late=50, seed=0):
    rng = np.random.default_rng(seed)
    on = pd.DataFrame({
        "is_delivered": 1, "is_late": 0,
        "review_score": rng.choice([4, 5], n_on_time),
        "days_late": rng.integers(-20, 0, n_on_time),
    })
    late = pd.DataFrame({
        "is_delivered": 1, "is_late": 1,
        "review_score": rng.choice([1, 2, 3], n_late),
        "days_late": rng.integers(1, 15, n_late),
    })
    df = pd.concat([on, late], ignore_index=True)
    n = len(df)
    df["delivery_days"] = 10 + df["days_late"].clip(lower=0) + rng.normal(0, 1, n)
    df["gmv"] = rng.uniform(20, 400, n)
    df["freight_revenue"] = df["gmv"] * rng.uniform(.05, .3, n)
    df["item_count"] = rng.integers(1, 3, n)
    df["max_installments"] = rng.integers(1, 10, n)
    return df


def test_delivered_with_review_filters_undelivered_and_unreviewed():
    df = _orders(10, 5)
    extra = df.iloc[:2].assign(is_delivered=0, is_late=np.nan)
    no_review = df.iloc[:1].assign(review_score=np.nan)
    out = delivered_with_review(pd.concat([df, extra, no_review]))
    assert len(out) == 15
    assert out["is_late"].dtype == bool


def test_negative_review_flag_is_one_or_two_stars():
    out = delivered_with_review(_orders())
    assert (out.loc[out["review_score"] <= 2, "negative_review"] == 1).all()
    assert (out.loc[out["review_score"] >= 3, "negative_review"] == 0).all()


def test_late_delivery_tests_detects_gap():
    rows = {r["test"]: r for r in late_delivery_tests(delivered_with_review(_orders()))}
    assert rows["avg review: late"]["value"] < rows["avg review: on-time"]["value"]
    assert rows["Mann-Whitney U (late < on-time)"]["p_value"] < 0.001
    assert rows["orders: late"]["value"] == 50


def test_negative_review_model_learns_signal():
    rows, coefs = negative_review_model(delivered_with_review(_orders(400, 100)))
    auc = next(r["value"] for r in rows if "ROC-AUC" in r["test"])
    assert auc > 0.8
    assert set(coefs["feature"]) == {"days_late", "delivery_days", "freight_share",
                                     "item_count", "max_installments", "log_gmv"}
