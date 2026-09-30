variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "db_name" {
  type    = string
  default = "conduit"
}

variable "db_username" {
  type    = string
  default = "conduit"
}

variable "instance_class" {
  description = "db.t4g.micro is Free-Tier eligible; bump up if you need more headroom"
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "multi_az" {
  description = "true = standby replica in a second AZ, automatic failover. Roughly doubles RDS cost."
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  type    = number
  default = 7
}

variable "deletion_protection" {
  description = "Set to true once this is a real production database you don't want 'terraform destroy' to touch by accident"
  type        = bool
  default     = false
}

variable "engine_version" {
  type    = string
  default = "16.4"
}
