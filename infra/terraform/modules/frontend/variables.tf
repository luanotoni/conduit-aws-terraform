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
