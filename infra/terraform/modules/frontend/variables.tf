variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "alb_dns_name" {
  description = "API origin for the /api/* behavior"
  type        = string
}

variable "access_logs_bucket_domain_name" {
  description = "S3 bucket (its bucket_domain_name) for CloudFront standard logs. Empty disables them."
  type        = string
  default     = ""
}
