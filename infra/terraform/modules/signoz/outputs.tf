output "otlp_endpoint" {
  description = "OTLP/HTTP base URL for OTEL_EXPORTER_OTLP_ENDPOINT"
  value       = "http://${local.dns_name}:4318"
}

output "instance_id" {
  description = "Target for `aws ssm start-session` (UI: port forwarding to 8080)"
  value       = aws_instance.signoz.id
}

output "security_group_id" {
  value = aws_security_group.signoz.id
}
