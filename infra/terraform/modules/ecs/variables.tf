variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "container_port" {
  type    = number
  default = 8000
}

variable "health_check_path" {
  type    = string
  default = "/healthz"
}

variable "task_cpu" {
  description = "Fargate task-level CPU units (256 = .25 vCPU)"
  type        = string
  default     = "256"
}

variable "task_memory" {
  description = "Fargate task-level memory in MB"
  type        = string
  default     = "512"
}

variable "desired_count" {
  type    = number
  default = 2
}

variable "min_capacity" {
  type    = number
  default = 2
}

variable "max_capacity" {
  type    = number
  default = 6
}

variable "cpu_target_value" {
  description = "Target-tracking autoscaling: keep average CPU near this %"
  type        = number
  default     = 60
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "db_credentials_secret_arn" {
  description = "ARN of the Secrets Manager secret from the database module, injected as POSTGRES_* env vars"
  type        = string
}

variable "extra_allowed_hosts" {
  description = "Comma-separated extra hosts (your real domain, once you have one). The ALB's own DNS name is always included automatically."
  type        = string
  default     = ""
}

variable "cors_allowed_origins" {
  type    = string
  default = "http://localhost:4100"
}

variable "enable_https" {
  description = "Requires acm_certificate_arn to be set. Leave false to stand the project up quickly on plain HTTP via the ALB's DNS name."
  type        = bool
  default     = false
}

variable "acm_certificate_arn" {
  type    = string
  default = ""
}
