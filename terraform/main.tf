# Demo environment: AWS infra instrumented THE EXPENSIVE WAY on purpose.
# Every anti-pattern here is detected by scripts/datadog_usage_audit.py
# and fixed in audit/PLAYBOOK.md.
#
# DO NOT use this as a reference for production Datadog config.

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    datadog = {
      source  = "DataDog/datadog"
      version = "~> 3.40"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "datadog" {
  api_key = var.datadog_api_key
  app_key = var.datadog_app_key
  api_url = var.datadog_api_url
}

# ------------------------------------------------------------------
# ANTI-PATTERN 2: single log index, 30-day retention, zero exclusion
# filters. Everything ingested gets indexed, including debug logs
# and health checks. PLAYBOOK §2 shows the fixed version.
# ------------------------------------------------------------------
resource "datadog_logs_index" "expensive_default" {
  name           = "main"
  daily_limit    = 999999999
  retention_days = 30

  filter {
    query = "*" # index absolutely everything
  }
  # (fixed version adds exclusion_filter blocks for status:debug,
  #  health checks, and 90% sampling of 2xx access logs)
}

# ------------------------------------------------------------------
# ANTI-PATTERN 3: APM ingestion at 100%, no retention filters.
# ------------------------------------------------------------------
resource "datadog_apm_retention_filter" "keep_everything" {
  name    = "keep-everything"
  enabled = true
  rate    = 1.0 # 100% — the fixed version keeps errors + p95 latency only
  filter {
    query = "*"
  }
  filter_type = "spans-sampling-processor"
}

# ------------------------------------------------------------------
# Demo workload: EC2 instances running containers that emit
# ANTI-PATTERN 1 (high-cardinality custom metrics tagged by
# request_id and container hostname) and ANTI-PATTERN 5
# (cron jobs registering a unique service name per run).
# See modules/ for the workload definitions.
# ------------------------------------------------------------------
module "noisy_workload" {
  source          = "./modules/noisy_workload"
  aws_region      = var.aws_region
  datadog_api_key = var.datadog_api_key
  instance_count  = 2
}

module "cron_chaos" {
  source          = "./modules/cron_chaos"
  aws_region      = var.aws_region
  datadog_api_key = var.datadog_api_key
}

# ------------------------------------------------------------------
# The monitor every org should have but almost none do:
# alert when ingestion anomalies spike (cost guardrail).
# ------------------------------------------------------------------
resource "datadog_monitor" "log_ingestion_guardrail" {
  name    = "[COST] Log ingestion anomaly"
  type    = "query alert"
  message = <<-EOT
    Log ingestion is anomalously high — a deploy probably started spamming.
    Check Logs > Configuration > Indexes before this becomes next month's bill.
    @slack-platform-team
  EOT

  query = "sum(last_4h):anomalies(sum:datadog.estimated_usage.logs.ingested_bytes{*}.as_count(), 'agile', 3) >= 1"

  monitor_thresholds {
    critical = 1
  }
  tags = ["team:platform", "service:observability", "env:demo", "cost:guardrail"]
}
