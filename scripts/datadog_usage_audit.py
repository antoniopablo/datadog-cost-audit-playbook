#!/usr/bin/env python3
"""
Datadog Usage Audit — ranks your top cost drivers via the Datadog API.

Usage:
    export DD_API_KEY=... DD_APP_KEY=...
    python datadog_usage_audit.py --site datadoghq.eu [--days 30]

Requires: requests (pip install -r requirements.txt)
"""
import argparse
import os
import sys
from datetime import datetime, timedelta, timezone

import requests


def api(site: str, path: str, params: dict | None = None) -> dict:
    r = requests.get(
        f"https://api.{site}{path}",
        headers={
            "DD-API-KEY": os.environ["DD_API_KEY"],
            "DD-APPLICATION-KEY": os.environ["DD_APP_KEY"],
        },
        params=params or {},
        timeout=30,
    )
    r.raise_for_status()
    return r.json()


def section(title: str) -> None:
    print(f"\n{'=' * 60}\n  {title}\n{'=' * 60}")


def audit_custom_metrics(site: str) -> None:
    """Top custom metrics by series count (cardinality offenders)."""
    section("1. CUSTOM METRICS — top cardinality offenders")
    data = api(site, "/api/v2/metrics", {"filter[configured]": "false", "page[size]": 100})
    metrics = [m["id"] for m in data.get("data", [])]
    ranked = []
    for name in metrics[:100]:
        try:
            vol = api(site, f"/api/v2/metrics/{name}/estimate")
            attrs = vol.get("data", {}).get("attributes", {})
            count = attrs.get("estimated_output_series", 0)
            ranked.append((count, name))
        except requests.HTTPError:
            continue
    ranked.sort(reverse=True)
    print(f"{'series':>10}  metric")
    for count, name in ranked[:20]:
        flag = "  <-- REVIEW" if count > 5000 else ""
        print(f"{count:>10}  {name}{flag}")
    print("\nFix: drop high-cardinality tags via Metrics without Limits,")
    print("aggregate client-side, delete metrics unqueried for 90d (see PLAYBOOK §1).")


def audit_usage_summary(site: str, days: int) -> None:
    """Billable usage over the window: hosts, logs, custom metrics, APM."""
    section("2. USAGE SUMMARY (billable dimensions)")
    end = datetime.now(timezone.utc)
    start = end - timedelta(days=days)
    data = api(
        site,
        "/api/v1/usage/summary",
        {"start_month": start.strftime("%Y-%m"), "end_month": end.strftime("%Y-%m")},
    )
    for month in data.get("usage", []):
        print(f"\nMonth: {month.get('date', '?')[:7]}")
        rows = [
            ("Infra host (top99p)", month.get("infra_host_top99p")),
            ("APM hosts (top99p)", month.get("apm_host_top99p")),
            ("Custom metrics (avg)", month.get("custom_ts_avg")),
            ("Indexed logs (events)", month.get("indexed_events_count_sum")),
            ("Ingested logs (bytes)", month.get("ingested_events_bytes_sum")),
            ("Indexed spans", month.get("indexed_spans_sum")),
            ("Ingested spans (bytes)", month.get("ingested_spans_bytes_sum")),
            ("RUM sessions", month.get("rum_total_session_count_sum")),
        ]
        for label, value in rows:
            if value:
                print(f"  {label:<28}{value:,}")


def audit_log_indexes(site: str) -> None:
    """Indexes without exclusion filters = money leak."""
    section("3. LOG INDEXES — exclusion filter check")
    data = api(site, "/api/v1/logs/config/indexes")
    for idx in data.get("indexes", []):
        name = idx.get("name")
        retention = idx.get("num_retention_days")
        filters = idx.get("exclusion_filters", [])
        active = [f for f in filters if f.get("is_enabled")]
        flag = "  <-- NO ACTIVE EXCLUSION FILTERS" if not active else ""
        print(f"  index={name:<20} retention={retention}d  filters={len(active)}{flag}")
    print("\nFix: exclusion filters on debug/info + sampling on access logs (PLAYBOOK §2).")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--site", default="datadoghq.com", help="datadoghq.com | datadoghq.eu")
    parser.add_argument("--days", type=int, default=30)
    args = parser.parse_args()

    for var in ("DD_API_KEY", "DD_APP_KEY"):
        if var not in os.environ:
            sys.exit(f"Missing env var: {var}")

    print(f"Datadog Usage Audit — site={args.site}, window={args.days}d")
    audit_usage_summary(args.site, args.days)
    audit_custom_metrics(args.site)
    audit_log_indexes(args.site)
    print("\nDone. Full remediation steps: audit/PLAYBOOK.md")


if __name__ == "__main__":
    main()
