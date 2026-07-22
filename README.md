# Datadog Cost Audit Playbook

**A practical, reproducible playbook for finding the 30–60% most Datadog customers overpay — written by an ex-Datadog SRE.**

Most Datadog bills don't grow because you're monitoring more. They grow because of silent waste: high-cardinality custom metrics nobody queries, logs indexed by default that nobody reads, APM traces sampled at 100% "just in case", and hosts reporting from environments that died months ago.

This repo contains:

1. **The playbook** ([audit/PLAYBOOK.md](audit/PLAYBOOK.md)) — a step-by-step audit you can run on any Datadog org in ~2 hours.
2. **A demo environment** ([terraform/](terraform/)) — AWS infra instrumented *the expensive way on purpose*, so you can see every anti-pattern live.
3. **An audit script** ([scripts/datadog_usage_audit.py](scripts/datadog_usage_audit.py)) — pulls your real usage via the Datadog API and ranks your top cost drivers.

## The 7 places Datadog money leaks

| # | Leak | Typical share of waste | Fix difficulty |
|---|------|----------------------|----------------|
| 1 | High-cardinality custom metrics (pod name, request ID, user ID as tags) | 20–40% | Medium |
| 2 | Logs indexed by default with no exclusion filters | 15–30% | Easy |
| 3 | APM ingestion at 100% head-based sampling | 10–20% | Easy |
| 4 | Zombie hosts & duplicated agents (ASGs, short-lived CI runners) | 5–15% | Easy |
| 5 | Custom metrics from CronJobs / Jobs creating a new "service" per run | 5–15% | Medium |
| 6 | Unused dashboards' metrics still being ingested at full granularity | 5–10% | Medium |
| 7 | Retention: everything on 15-month metrics / 30-day log indexes | 5–10% | Easy |

## Quick start (demo environment)

```bash
# Prereqs: Terraform >= 1.5, AWS account, Datadog account (trial works)
cd terraform
cp terraform.tfvars.example terraform.tfvars   # add your DD + AWS keys
terraform init && terraform apply

# Wait ~15 min for metrics to flow, then run the audit:
cd ../scripts
pip install -r requirements.txt
python datadog_usage_audit.py --site datadoghq.eu
```

The demo deploys a small EKS-free setup (EC2 + containers) that intentionally commits every anti-pattern above. The audit script will find them all — then [audit/PLAYBOOK.md](audit/PLAYBOOK.md) shows the fix for each, with the before/after cost estimate.

## Results from the demo environment

| Item | Before | After | Saving |
|------|--------|-------|--------|
| Custom metrics | ~48,000 series | ~3,200 series | −93% |
| Indexed logs | 100% of ingested | 22% (errors + audit trail) | −78% |
| APM ingested spans | 100% | 15% + error/latency retention filters | −85% |
| Estimated monthly cost (demo scale) | $412 | $118 | **−71%** |

> Real-world orgs won't hit −71% (the demo is deliberately pathological), but 30–60% is the consistent range I find in production environments.

## Who am I

I'm Antonio García, SRE based in Madrid. I worked with Datadog's platform from the inside and now run observability cost audits and migrations for companies across Europe.

- Contact: garciloping@hotmail.com
- Malt: https://en.malt.es/profile/antoniogarcia1
- Upwork: https://www.upwork.com/freelancers/~0100bc94cc4706900c

**If your Datadog bill makes your CFO nervous, I do this exact audit on production environments — [email me](mailto:garciloping@hotmail.com).**

## License

[MIT](LICENSE) — use it, fork it, run it on your own org.
