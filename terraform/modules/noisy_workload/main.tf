# ANTI-PATTERN 1 generator: high-cardinality custom metrics.
# Cheap spot instances running a DogStatsD emitter that tags every
# metric with request_id + hostname — exploding series count on purpose.

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
variable "instance_count" {
  type    = number
  default = 2
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

resource "aws_security_group" "noisy_egress" {
  name        = "dd-audit-demo-noisy-egress"
  description = "Minimal SG: only egress for noisy workload"
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_instance" "noisy" {
  count         = var.instance_count
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

  vpc_security_group_ids = [aws_security_group.noisy_egress.id]

  tags = {
    Name    = "dd-audit-demo-noisy-${count.index}"
    Project = "datadog-cost-audit-playbook"
    # NOTE: deliberately missing team/env/service tags -> PLAYBOOK §6
  }
}

output "instance_ids" {
  value = aws_instance.noisy[*].id
}
