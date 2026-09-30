variable "project_name" {
  description = "Used to prefix/tag every resource, e.g. 'conduit'"
  type        = string
}

variable "environment" {
  description = "e.g. 'prod'"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "At least 2 AZs, for Multi-AZ resilience"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "One per AZ, hosts the ALB and NAT Gateways"
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "One per AZ, hosts ECS tasks and RDS"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "single_nat_gateway" {
  description = "true = one shared NAT Gateway (cheaper, single point of failure). false = one NAT Gateway per AZ (production-grade HA, ~$32/mo extra per gateway)."
  type        = bool
  default     = false
}
