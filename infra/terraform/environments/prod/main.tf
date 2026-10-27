module "network" {
  source = "../../modules/network"

  project_name       = var.project_name
  environment        = var.environment
  availability_zones = var.availability_zones
  single_nat_gateway = var.single_nat_gateway
}

module "logs" {
  source = "../../modules/logs"

  project_name = var.project_name
  environment  = var.environment
}

module "database" {
  source = "../../modules/database"

  project_name          = var.project_name
  environment           = var.environment
  vpc_id                = module.network.vpc_id
  private_subnet_ids    = module.network.private_subnet_ids
  multi_az              = var.db_multi_az
  instance_class        = var.db_instance_class
  backup_retention_days = var.db_backup_retention_days
  deletion_protection   = false # flip to true once this holds data you actually care about
}

module "ecs" {
  source = "../../modules/ecs"

  project_name               = var.project_name
  environment                = var.environment
  vpc_id                     = module.network.vpc_id
  vpc_cidr                   = module.network.vpc_cidr
  public_subnet_ids          = module.network.public_subnet_ids
  private_subnet_ids         = module.network.private_subnet_ids
  db_credentials_secret_arn  = module.database.credentials_secret_arn
  min_capacity               = var.ecs_min_capacity
  max_capacity               = var.ecs_max_capacity
  enable_https               = var.enable_https
  acm_certificate_arn        = var.acm_certificate_arn
  extra_allowed_hosts        = var.extra_allowed_hosts # your real domain, once you have one
  cors_allowed_origins       = var.cors_allowed_origins
  access_logs_bucket         = module.logs.bucket_id
  restrict_alb_to_cloudfront = var.restrict_alb_to_cloudfront
  otlp_endpoint              = var.enable_signoz ? module.signoz[0].otlp_endpoint : ""
}

# Self-hosted SigNoz for distributed tracing. Complements CloudWatch (logs,
# metrics, alarms), which stays the source of truth for alerting.
module "signoz" {
  source = "../../modules/signoz"
  count  = var.enable_signoz ? 1 : 0

  project_name                = var.project_name
  environment                 = var.environment
  vpc_id                      = module.network.vpc_id
  private_subnet_id           = module.network.private_subnet_ids[0]
  ecs_tasks_security_group_id = module.ecs.ecs_tasks_security_group_id
  instance_type               = var.signoz_instance_type
}

# --- Wiring that would otherwise be a circular module dependency ------------------
# The database module creates its security group without any ingress rule, and
# the ECS module creates its tasks' security group independently. This is the
# one rule that connects them: "the DB only accepts traffic from ECS tasks."

resource "aws_security_group_rule" "ecs_to_db" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = module.database.security_group_id
  source_security_group_id = module.ecs.ecs_tasks_security_group_id
  description              = "Django containers to Postgres"
}

module "waf" {
  source = "../../modules/waf"

  project_name = var.project_name
  environment  = var.environment
  alb_arn      = module.ecs.alb_arn
}

module "monitoring" {
  source = "../../modules/monitoring"

  project_name            = var.project_name
  environment             = var.environment
  alert_email             = var.alert_email
  ecs_cluster_name        = module.ecs.cluster_name
  ecs_service_name        = module.ecs.service_name
  alb_arn_suffix          = module.ecs.alb_arn_suffix
  target_group_arn_suffix = module.ecs.target_group_arn_suffix
  db_instance_id          = module.database.db_instance_id

  app_log_group_name         = module.ecs.log_group_name
  db_log_group_name          = module.database.log_group_name
  flow_logs_log_group_name   = module.network.flow_logs_log_group_name
  waf_web_acl_name           = module.waf.web_acl_name
  cloudfront_distribution_id = module.frontend.distribution_id
}

module "frontend" {
  source = "../../modules/frontend"

  project_name = var.project_name
  environment  = var.environment
  alb_dns_name = module.ecs.alb_dns_name

  access_logs_bucket_domain_name = module.logs.bucket_domain_name
}
