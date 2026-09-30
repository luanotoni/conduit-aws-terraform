output "security_group_id" {
  value = aws_security_group.db.id
}

output "endpoint" {
  value = aws_db_instance.this.address
}

output "port" {
  value = aws_db_instance.this.port
}

output "credentials_secret_arn" {
  description = "Pass this to the ECS module so the task definition can inject POSTGRES_* env vars via `secrets`"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "db_instance_id" {
  value = aws_db_instance.this.id
}
