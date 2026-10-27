"""Statistical analysis and charts on top of the SQL pipeline outputs.

Reads the CSVs written by run_pipeline.sh (no database driver needed):
  * outputs/*.csv           - results of the SQL business analyses
  * powerbi/data/*.csv      - the cleaned star schema

Produces:
  * outputs/stats_summary.csv  - hypothesis tests + regression results
  * reports/figures/*.png      - charts used in the README

Run from the repo root:  python -m src.analysis
"""

from __future__ import annotations

from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from scipy import stats
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import roc_auc_score
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "outputs"
FIG = ROOT / "reports" / "figures"

BLUE, RED, GREY = "#2563eb", "#dc2626", "#9ca3af"


# --------------------------------------------------------------------- data
def load_orders() -> pd.DataFrame:
    """Order-level fact table (valid sales inside the analysis window)."""
    return pd.read_csv(ROOT / "powerbi" / "data" / "fct_orders.csv",
                       parse_dates=["order_date", "order_month"])


def delivered_with_review(orders: pd.DataFrame) -> pd.DataFrame:
    """Delivered orders that have a review score and a known lateness."""
    # booleans are exported as 1/0 so Power BI can sum/average them
    d = orders[(orders["is_delivered"] == 1) & orders["review_score"].notna()
               & orders["is_late"].notna()].copy()
    d["is_late"] = d["is_late"].astype(bool)
    d["negative_review"] = (d["review_score"] <= 2).astype(int)
    return d


# -------------------------------------------------------------------- stats
def late_delivery_tests(d: pd.DataFrame) -> list[dict]:
    """Is the review score of late orders significantly lower?

    * Mann-Whitney U on review score (ordinal 1-5, so non-parametric).
    * Chi-square test on the negative-review rate (1-2 stars).
    """
    late, on_time = d[d["is_late"]], d[~d["is_late"]]

    u = stats.mannwhitneyu(late["review_score"], on_time["review_score"],
                           alternative="less")
    table = pd.crosstab(d["is_late"], d["negative_review"])
    chi2, chi_p, _, _ = stats.chi2_contingency(table)

    neg_late = late["negative_review"].mean()
    neg_on = on_time["negative_review"].mean()
    return [
        {"test": "orders: on-time", "value": len(on_time), "p_value": None},
        {"test": "orders: late", "value": len(late), "p_value": None},
        {"test": "late share of delivered orders (%)",
         "value": round(100 * len(late) / len(d), 2), "p_value": None},
        {"test": "avg review: on-time", "value": round(on_time["review_score"].mean(), 2), "p_value": None},
        {"test": "avg review: late", "value": round(late["review_score"].mean(), 2), "p_value": None},
        {"test": "Mann-Whitney U (late < on-time)", "value": float(u.statistic), "p_value": float(u.pvalue)},
        {"test": "negative-review rate: on-time (%)", "value": round(100 * neg_on, 1), "p_value": None},
        {"test": "negative-review rate: late (%)", "value": round(100 * neg_late, 1), "p_value": None},
        {"test": "negative-review rate ratio (late / on-time)",
         "value": round(neg_late / neg_on, 2), "p_value": None},
        {"test": "chi-square (lateness x negative review)", "value": round(chi2, 1), "p_value": float(chi_p)},
    ]


FEATURES = ["days_late", "delivery_days", "freight_share", "item_count",
            "max_installments", "log_gmv"]


def negative_review_model(d: pd.DataFrame, seed: int = 42) -> tuple[list[dict], pd.DataFrame]:
    """Logistic regression: which order factors predict a 1-2 star review?

    Features are standardised so coefficients are comparable; reported as
    odds ratios per 1 standard deviation. Evaluated with ROC-AUC on a
    stratified 25% hold-out set.
    """
    m = d.copy()
    m["freight_share"] = m["freight_revenue"] / m["gmv"]
    m["log_gmv"] = np.log1p(m["gmv"])
    m["max_installments"] = m["max_installments"].fillna(1)
    m = m.dropna(subset=FEATURES)

    X_train, X_test, y_train, y_test = train_test_split(
        m[FEATURES], m["negative_review"], test_size=0.25,
        stratify=m["negative_review"], random_state=seed)
    scaler = StandardScaler().fit(X_train)
    model = LogisticRegression(max_iter=1000, class_weight="balanced")
    model.fit(scaler.transform(X_train), y_train)
    auc = roc_auc_score(y_test, model.predict_proba(scaler.transform(X_test))[:, 1])

    coefs = (pd.DataFrame({"feature": FEATURES,
                           "odds_ratio_per_sd": np.exp(model.coef_[0]).round(3)})
             .sort_values("odds_ratio_per_sd", ascending=False))
    rows = [{"test": "logistic regression ROC-AUC (hold-out)", "value": round(auc, 3), "p_value": None},
            {"test": "logistic regression training rows", "value": len(X_train), "p_value": None}]
    rows += [{"test": f"odds ratio per SD: {r.feature}", "value": r.odds_ratio_per_sd, "p_value": None}
             for r in coefs.itertuples()]
    return rows, coefs


# ------------------------------------------------------------------- charts
def _save(fig, name: str) -> None:
    fig.tight_layout()
    fig.savefig(FIG / name, dpi=150)
    plt.close(fig)


def chart_monthly_gmv() -> None:
    m = pd.read_csv(OUT / "01_monthly_revenue.csv", parse_dates=["order_month"])
    fig, ax = plt.subplots(figsize=(9, 4))
    ax.bar(m["order_month"], m["gmv"] / 1e6, width=20, color=BLUE, alpha=.8, label="Monthly GMV")
    ax.plot(m["order_month"], m["gmv_3m_avg"] / 1e6, color=RED, lw=2, label="3-month moving avg")
    peak = m.loc[m["gmv"].idxmax()]
    ax.annotate(f"Black Friday\n+{peak.gmv_mom_pct:.0f}% MoM", (peak.order_month, peak.gmv / 1e6),
                xytext=(0, 6), textcoords="offset points", ha="center", fontsize=9)
    ax.set_ylim(0, m["gmv"].max() / 1e6 * 1.25)  # headroom for the label
    ax.set_ylabel("GMV (BRL millions)")
    ax.set_title("Monthly GMV, Jan 2017 - Aug 2018")
    ax.legend(frameon=False)
    ax.spines[["top", "right"]].set_visible(False)
    _save(fig, "monthly_gmv.png")


def chart_delay_vs_review() -> None:
    d = pd.read_csv(OUT / "03_delivery_vs_reviews.csv")
    labels = d["delay_bucket"].str[3:]
    colors = [BLUE, BLUE, RED, RED, RED]
    fig, ax = plt.subplots(figsize=(8, 4))
    bars = ax.bar(labels, d["avg_review"], color=colors)
    for b, neg in zip(bars, d["pct_negative_reviews"]):
        ax.text(b.get_x() + b.get_width() / 2, b.get_height() + .05,
                f"{b.get_height():.2f}\n({neg:.0f}% 1-2 star)", ha="center", fontsize=8)
    ax.set_ylim(0, 5.2)
    ax.set_ylabel("Average review score")
    ax.set_title("Review score collapses once an order arrives late")
    ax.spines[["top", "right"]].set_visible(False)
    _save(fig, "delay_vs_review.png")


def chart_state_late_rate() -> None:
    s = pd.read_csv(OUT / "04_delivery_by_state.csv").sort_values("late_rate_pct")
    fig, ax = plt.subplots(figsize=(7, 5))
    colors = [RED if v >= 10 else GREY for v in s["late_rate_pct"]]
    ax.barh(s["customer_state"], s["late_rate_pct"], color=colors)
    ax.set_xlabel("Late-delivery rate (%)")
    ax.set_title("Late-delivery rate by customer state (>= 500 orders)")
    ax.spines[["top", "right"]].set_visible(False)
    _save(fig, "late_rate_by_state.png")


def chart_cohort_heatmap() -> None:
    c = pd.read_csv(OUT / "06_cohort_retention.csv", parse_dates=["cohort_month"])
    pivot = (c[c["month_number"].between(1, 6)]
             .pivot(index="cohort_month", columns="month_number", values="retention_pct"))
    fig, ax = plt.subplots(figsize=(7, 6))
    im = ax.imshow(pivot.values, cmap="Blues", aspect="auto")
    ax.set_xticks(range(pivot.shape[1]), [f"M+{i}" for i in pivot.columns])
    ax.set_yticks(range(pivot.shape[0]), pivot.index.strftime("%Y-%m"))
    for (i, j), v in np.ndenumerate(pivot.values):
        if not np.isnan(v):
            ax.text(j, i, f"{v:.1f}", ha="center", va="center", fontsize=7)
    fig.colorbar(im, ax=ax, label="% of cohort purchasing again")
    ax.set_title("Monthly cohort retention (months 1-6)")
    _save(fig, "cohort_retention.png")


def chart_rfm_segments() -> None:
    r = pd.read_csv(OUT / "07_rfm_segmentation.csv")
    fig, ax = plt.subplots(figsize=(8, 4))
    x = np.arange(len(r))
    ax.bar(x - .2, r["pct_customers"], .4, color=GREY, label="% of customers")
    ax.bar(x + .2, r["pct_gmv"], .4, color=BLUE, label="% of GMV")
    ax.set_xticks(x, r["segment"], rotation=20, ha="right")
    ax.set_ylabel("%")
    ax.set_title("RFM segments: share of customers vs share of revenue")
    ax.legend(frameon=False)
    ax.spines[["top", "right"]].set_visible(False)
    _save(fig, "rfm_segments.png")


def chart_odds_ratios(coefs: pd.DataFrame) -> None:
    c = coefs.sort_values("odds_ratio_per_sd")
    fig, ax = plt.subplots(figsize=(7, 4))
    colors = [RED if v > 1 else BLUE for v in c["odds_ratio_per_sd"]]
    ax.barh(c["feature"], c["odds_ratio_per_sd"], color=colors)
    ax.axvline(1, color="black", lw=1)
    ax.set_xlabel("Odds ratio of a 1-2 star review, per +1 SD")
    ax.set_title("What predicts a negative review? (logistic regression)")
    ax.spines[["top", "right"]].set_visible(False)
    _save(fig, "negative_review_drivers.png")


def main() -> None:
    FIG.mkdir(parents=True, exist_ok=True)
    orders = load_orders()
    d = delivered_with_review(orders)

    rows = late_delivery_tests(d)
    model_rows, coefs = negative_review_model(d)
    summary = pd.DataFrame(rows + model_rows)
    summary.to_csv(OUT / "stats_summary.csv", index=False)

    chart_monthly_gmv()
    chart_delay_vs_review()
    chart_state_late_rate()
    chart_cohort_heatmap()
    chart_rfm_segments()
    chart_odds_ratios(coefs)

    with pd.option_context("display.width", 120, "display.float_format", "{:.4g}".format):
        print(summary.to_string(index=False))
    print(f"\nCharts written to {FIG.relative_to(ROOT)}/")


if __name__ == "__main__":
    main()
