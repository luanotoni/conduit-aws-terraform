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
  # `identifier`, not `id`: since AWS provider v5 `id` is the DbiResourceId
  # (db-XXXX), which is not what the DBInstanceIdentifier metric dimension uses.
  value = aws_db_instance.this.identifier
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.postgresql.name
}
