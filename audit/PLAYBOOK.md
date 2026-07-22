# The Audit Playbook

Step-by-step. Each section: how to detect, how to quantify, how to fix. Run top to bottom — items are ordered by typical impact.

---

## 0. Baseline (15 min)

Before touching anything, snapshot current spend and usage:

- **Plan & Usage** page → export last 3 months (Usage tab → CSV).
- Note billable: infra hosts, custom metrics, indexed log volume (GB + events), APM hosts + ingested/indexed spans, RUM sessions, synthetics runs.
- Run `scripts/datadog_usage_audit.py` for the API-level breakdown.

Rule of thumb for attribution: if you can't say which team/service owns a cost line, tag hygiene is your first problem (see §6).

## 1. High-cardinality custom metrics (biggest win, usually)

**Detect:**
- Metrics Summary → sort by cardinality. Anything >5,000 series deserves a reason to exist.
- Look for tags like `pod_name`, `container_id`, `request_id`, `user_id`, `path` with raw IDs. These explode series count: `metric × tag values = series`, and you pay per series.

**Quantify:** custom metrics beyond the per-host allowance are billed per 100 series. The audit script prints your top 20 offenders and their series count.

**Fix:**
- Drop the offending tags with Metrics without Limits™ (tag configuration) — keeps ingestion, stops indexing what you don't query.
- At the source: don't tag by pod/instance for business metrics; aggregate before emitting (DogStatsD client-side aggregation).
- Delete metrics nobody has queried in 90 days (Metrics Summary shows last-queried).

## 2. Log indexing without exclusion filters

**Detect:** Logs → Configuration → Indexes. If there's one index, no exclusion filters, and 30-day retention on everything — this is the leak.

**Quantify:** indexed events × retention tier price vs. ingestion-only price. Most orgs read <5% of what they index.

**Fix (in order):**
1. Exclusion filters: drop `status:debug`/`status:info` from high-volume services (keep ERROR + WARN), sample the rest (e.g. keep 10% of 2xx access logs).
2. Route noisy-but-needed logs to a **Flex Logs / archive** tier instead of standard indexing.
3. Multiple indexes with different retention: errors 30d, access logs 7d, audit logs to archive with rehydration.
4. At the source: stop shipping health checks and readiness probes entirely (agent-level `exclude_paths` or pipeline filter).

## 3. APM sampling

**Detect:** APM → Ingestion Control. If ingestion is at or near 100% with no retention filters — leak.

**Fix:**
- Head-based sampling to 10–20% baseline.
- Retention filters to keep 100% of errors and p95+ latency traces (you lose nothing you'd actually look at).
- Check `DD_APM_ENABLED` on services nobody traces; disable where APM adds nothing.

## 4. Zombie & duplicate hosts

**Detect:** Infrastructure list filtered by `?status:muted` and hosts reporting but not tied to any live deploy. Cross-check with your ASG/instance inventory. Common sources: CI runners with agents baked into the AMI, autoscaling churn (each short-lived instance bills as a host-hour), forgotten dev boxes.

**Fix:** remove the agent from ephemeral images, use the container agent where suitable, and alert on `datadog.agent.running` from hosts outside your IaC inventory.

## 5. CronJob / batch "service explosion"

**Detect:** APM service list or metric tags with hundreds of services named `job-xyz-1234abcd`. Kubernetes Jobs create unique pod names; if service naming inherits them, every run is a "new service" with its own metric series.

**Fix:** normalize service names via `DD_SERVICE` env or admission controller; drop the run-ID from tags. In the demo environment, `terraform/modules/cron_chaos` reproduces this exact pattern.

## 6. Tag hygiene (enables everything else)

Cost attribution requires 3 tags everywhere: `team`, `service`, `env`. Enforce required tags at the IaC level (a `default_tags` block on the AWS provider, or a policy check in CI) — see the deliberately incomplete tagging on the instances in `terraform/modules/noisy_workload` and `terraform/modules/cron_chaos` for what *not* to do. Once tags are consistent, Usage Attribution can split the bill by team — which is what turns a one-off audit into permanent cost control.

## 7. Retention & commitment review

- Metrics you only dashboard weekly don't need 15-month full granularity.
- Move from on-demand to annual commit for stable baseline usage (typical 20–30% discount), keep burst on on-demand.
- Re-run this audit before every renewal: negotiate with the cleaned-up numbers, not the inflated ones.

---

## Deliverable template

When I run this for clients, the output is:

1. **Findings report** — each leak, quantified in €/month, with evidence screenshots.
2. **Fix implementation** — PRs against their IaC (never console-only changes).
3. **Guardrails** — monitors on ingestion anomalies + usage attribution dashboards so it doesn't regress.
4. **Handover doc** — what changed, why, and how to keep it that way.
