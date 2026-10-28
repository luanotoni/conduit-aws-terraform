variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_id" {
  description = "Private subnet for the instance; it pulls images through the NAT Gateway"
  type        = string
}

variable "ecs_tasks_security_group_id" {
  description = "The only source allowed to send OTLP to the collector"
  type        = string
}

variable "instance_type" {
  description = "ClickHouse, Postgres, the collector and SigNoz share it; SigNoz asks for at least 4 GiB for Docker"
  type        = string
  default     = "m7i-flex.large"
}

variable "volume_size_gb" {
  type    = number
  default = 30
}

variable "signoz_version" {
  # Used on first boot only (user_data is ignored afterwards). To upgrade a
  # running instance, edit /opt/signoz/casting.yaml over SSM and re-run
  # `foundryctl cast -f casting.yaml`; then bump these to match.
  description = "signoz/signoz image tag, from https://github.com/SigNoz/signoz/releases"
  type        = string
  default     = "v0.146.0"
}

variable "collector_version" {
  description = "signoz/signoz-otel-collector image tag; bump together with signoz_version"
  type        = string
  default     = "v0.144.14"
}
