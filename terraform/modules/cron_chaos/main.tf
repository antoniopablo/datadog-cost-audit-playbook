# ANTI-PATTERN 5 generator: "service explosion" from batch jobs.
# A cron that registers a UNIQUE service name per run (job-<timestamp>),
# exactly what happens when K8s Jobs inherit pod names as DD_SERVICE.

terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}

variable "aws_region" { type = string }
variable "datadog_api_key" {
  type      = string
  sensitive = true
}
variable "datadog_site" {
  type    = string
  default = "datadoghq.eu"
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }
}

data "aws_vpc" "default" {
  default = true
}

resource "aws_security_group" "cron_egress" {
  name        = "dd-audit-demo-cron-egress"
  description = "Minimal SG: only egress for cron chaos workload"
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_instance" "cron_chaos" {
  ami           = data.aws_ami.al2023.id
  instance_type = "t3.micro"

  instance_market_options {
    market_type = "spot"
    spot_options {
      spot_instance_type             = "one-time"
      instance_interruption_behavior = "terminate"
    }
  }

  user_data = templatefile("${path.module}/templates/user_data.sh.tftpl", {
    datadog_api_key = var.datadog_api_key
    datadog_site    = var.datadog_site
  })

  vpc_security_group_ids = [aws_security_group.cron_egress.id]

  tags = {
    Name    = "dd-audit-demo-cron-chaos"
    Project = "datadog-cost-audit-playbook"
  }
}

output "instance_id" {
  value = aws_instance.cron_chaos.id
}
