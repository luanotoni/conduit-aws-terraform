locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

resource "random_password" "db_password" {
  length  = 32
  special = false # avoid characters RDS/JDBC connection strings choke on
}

# --- Network placement ----------------------------------------------------------

resource "aws_db_subnet_group" "this" {
  name       = "${local.name_prefix}-db-subnets"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${local.name_prefix}-db-subnets"
  }
}

resource "aws_security_group" "db" {
  name_prefix = "${local.name_prefix}-db-"
  description = "RDS Postgres - ingress attached from the root module to avoid a circular dependency with the ECS module security group"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${local.name_prefix}-db-sg"
  }
}

# --- RDS instance -----------------------------------------------------------------

resource "aws_db_parameter_group" "this" {
  name_prefix = "${local.name_prefix}-pg16-"
  family      = "postgres16"

  parameter {
    name  = "log_min_duration_statement"
    value = "500" # log queries slower than 500ms, useful once you're debugging real latency
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "this" {
  identifier     = "${local.name_prefix}-db"
  engine         = "postgres"
  engine_version = var.engine_version

  instance_class    = var.instance_class
  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_password.result
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]
  parameter_group_name   = aws_db_parameter_group.this.name

  multi_az                = var.multi_az
  backup_retention_period = var.backup_retention_days
  backup_window           = "06:00-07:00" # UTC, chosen as a low-traffic window
  maintenance_window      = "mon:07:00-mon:08:00"

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = !var.deletion_protection
  final_snapshot_identifier = var.deletion_protection ? "${local.name_prefix}-db-final" : null

  performance_insights_enabled = true

  tags = {
    Name = "${local.name_prefix}-db"
  }
}

# --- Credentials, stored where ECS task definitions can reference them ------------
# The ECS task definition pulls these by ARN via `secrets` (not `environment`), so
# the plaintext password is never visible in the task definition JSON, the console,
# or `terraform show` output of anything other than this resource itself.

resource "aws_secretsmanager_secret" "db_credentials" {
  name_prefix = "${local.name_prefix}-db-credentials-"
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    POSTGRES_DB       = var.db_name
    POSTGRES_USER     = var.db_username
    POSTGRES_PASSWORD = random_password.db_password.result
    POSTGRES_HOST     = aws_db_instance.this.address
    POSTGRES_PORT     = tostring(aws_db_instance.this.port)
  })
}
