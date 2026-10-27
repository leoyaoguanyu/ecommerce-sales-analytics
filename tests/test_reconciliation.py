"""Reconciliation tests: every analysis output and the Power BI export must
agree on the same totals. Catches join fan-out, filter drift between
queries, and stale exports."""

from pathlib import Path

import pandas as pd
import pytest

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "outputs"
PBI = ROOT / "powerbi" / "data"

pytestmark = pytest.mark.skipif(not (PBI / "fct_orders.csv").exists(),
                                reason="run ./run_pipeline.sh first")


@pytest.fixture(scope="module")
def orders():
    return pd.read_csv(PBI / "fct_orders.csv")


def test_monthly_gmv_matches_fact_table(orders):
    monthly = pd.read_csv(OUT / "01_monthly_revenue.csv")
    assert monthly["gmv"].sum() == pytest.approx(orders["gmv"].sum(), abs=1)
    assert monthly["orders"].sum() == len(orders)


def test_category_gmv_matches_fact_table(orders):
    cats = pd.read_csv(OUT / "02_category_performance.csv")
    assert cats["gmv"].sum() == pytest.approx(orders["gmv"].sum(), abs=1)
    assert cats["cumulative_share_pct"].iloc[-1] == pytest.approx(100, abs=0.1)


def test_item_level_export_has_no_fan_out(orders):
    items = pd.read_csv(PBI / "fct_order_items.csv")
    assert items["line_gmv"].sum() == pytest.approx(orders["gmv"].sum(), abs=1)
    assert not items.duplicated(["order_id", "order_item_id"]).any()


def test_rfm_covers_every_customer_once(orders):
    rfm = pd.read_csv(OUT / "07_rfm_segmentation.csv")
    customers = pd.read_csv(PBI / "dim_customer.csv")
    assert rfm["customers"].sum() == orders["customer_unique_id"].nunique() == len(customers)
    assert rfm["gmv"].sum() == pytest.approx(orders["gmv"].sum(), abs=1)


def test_seller_tiers_sum_to_total(orders):
    tiers = pd.read_csv(OUT / "08_seller_concentration.csv")
    assert tiers["gmv"].sum() == pytest.approx(orders["gmv"].sum(), abs=1)


def test_cohort_month_zero_is_full_cohort():
    c = pd.read_csv(OUT / "06_cohort_retention.csv")
    m0 = c[c["month_number"] == 0]
    assert (m0["retention_pct"] == 100).all()


def test_blocking_data_quality_checks_pass():
    dq = pd.read_csv(OUT / "00_data_quality.csv")
    assert dq.loc[dq["severity"] == "blocking", "failing_rows"].sum() == 0
