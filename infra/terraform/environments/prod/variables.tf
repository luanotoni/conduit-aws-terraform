variable "project_name" {
  type    = string
  default = "conduit"
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "availability_zones" {
  description = "Pick 2 AZs available in your region"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "alert_email" {
  description = "You'll receive an SNS confirmation email after the first apply - you must click the link or alarms silently go nowhere"
  type        = string
}

# --- Cost/resilience toggles -----------------------------------------------------
# Defaults below match the "produção completa" scope. Flip these to cut cost
# fast if the deadline is closer than the AWS bill tolerance:
#   single_nat_gateway = true   -> saves ~$32/mo
#   db_multi_az        = false  -> roughly halves the RDS bill

variable "single_nat_gateway" {
  type    = bool
  default = false
}

variable "db_multi_az" {
  type    = bool
  default = true
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "ecs_min_capacity" {
  type    = number
  default = 2
}

variable "ecs_max_capacity" {
  type    = number
  default = 6
}

variable "enable_https" {
  description = "Requires acm_certificate_arn - leave false until you have a domain + validated ACM cert"
  type        = bool
  default     = false
}

variable "acm_certificate_arn" {
  type    = string
  default = ""
}

variable "extra_allowed_hosts" {
  description = "Comma-separated. Add your real domain here once you have one; the ALB's own DNS name always works without this."
  type        = string
  default     = ""
}

variable "db_backup_retention_days" {
  type    = number
  default = 1
}