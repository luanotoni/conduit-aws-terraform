output "alb_dns_name" {
  description = "Open this in a browser (http://) once the first deploy finishes"
  value       = module.ecs.alb_dns_name
}

output "ecr_repository_url" {
  description = "Where the CI/CD pipeline pushes Docker images"
  value       = module.ecs.ecr_repository_url
}

output "ecs_cluster_name" {
  value = module.ecs.cluster_name
}

output "ecs_service_name" {
  value = module.ecs.service_name
}

output "ecs_task_definition_family" {
  value = module.ecs.task_definition_family
}

output "cloudwatch_dashboard_url" {
  value = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${module.monitoring.dashboard_name}"
}

output "db_endpoint" {
  value = module.database.endpoint
}

output "private_subnet_ids" {
  description = "Needed by the CD pipeline to run the one-off migration task in the same network as the app"
  value       = module.network.private_subnet_ids
}

output "ecs_tasks_security_group_id" {
  value = module.ecs.ecs_tasks_security_group_id
}

output "frontend_url" {
  description = "Public URL of the React frontend (API is proxied under /api)"
  value       = "https://${module.frontend.distribution_domain_name}"
}

output "frontend_bucket_name" {
  value = module.frontend.bucket_name
}

output "frontend_distribution_id" {
  value = module.frontend.distribution_id
}

output "access_logs_bucket" {
  description = "ALB (alb/) and CloudFront (cloudfront/) access logs"
  value       = module.logs.bucket_id
}

output "signoz_ui_command" {
  description = "Opens the SigNoz UI on http://localhost:8080 through Session Manager"
  value       = var.enable_signoz ? "aws ssm start-session --target ${module.signoz[0].instance_id} --document-name AWS-StartPortForwardingSession --parameters portNumber=8080,localPortNumber=8080" : null
}
