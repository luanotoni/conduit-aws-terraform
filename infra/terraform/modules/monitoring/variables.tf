variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "alert_email" {
  description = "Where SNS sends alarm notifications. You'll get a confirmation email after the first apply - you must click it."
  type        = string
}

variable "ecs_cluster_name" {
  type = string
}

variable "ecs_service_name" {
  type = string
}

variable "alb_arn_suffix" {
  type = string
}

variable "target_group_arn_suffix" {
  type = string
}

variable "db_instance_id" {
  type = string
}

variable "app_log_group_name" {
  description = "CloudWatch log group the Django containers write to"
  type        = string
}

variable "db_log_group_name" {
  type = string
}

variable "flow_logs_log_group_name" {
  type = string
}

variable "waf_web_acl_name" {
  type = string
}

variable "cloudfront_distribution_id" {
  type = string
}
