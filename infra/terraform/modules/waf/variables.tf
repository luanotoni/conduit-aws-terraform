variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "alb_arn" {
  type = string
}

variable "rate_limit_per_5min" {
  description = "Requests from a single IP allowed in a rolling 5-minute window before it's temporarily blocked"
  type        = number
  default     = 2000
}
