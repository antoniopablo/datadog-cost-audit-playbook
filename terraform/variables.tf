variable "aws_region" {
  description = "AWS region for the demo environment"
  type        = string
  default     = "eu-west-1"
}

variable "datadog_api_key" {
  description = "Datadog API key"
  type        = string
  sensitive   = true
}

variable "datadog_app_key" {
  description = "Datadog application key"
  type        = string
  sensitive   = true
}

variable "datadog_api_url" {
  description = "Datadog API URL (EU: https://api.datadoghq.eu/)"
  type        = string
  default     = "https://api.datadoghq.eu/"
}
