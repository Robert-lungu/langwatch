# -----------------------------------------------------------------------------
# RDS PostgreSQL
# -----------------------------------------------------------------------------

# Get latest PostgreSQL 16.x available in the region (omit if rds_engine_version is set)
data "aws_rds_engine_version" "postgres" {
  count = var.rds_engine_version == "" ? 1 : 0

  engine             = "postgres"
  preferred_versions = ["16.13", "16.12", "16.11", "16.10", "16.9", "16.8", "16.6"]
}

locals {
  postgres_engine_version = var.rds_engine_version != "" ? var.rds_engine_version : data.aws_rds_engine_version.postgres[0].version
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-${var.environment}-db-subnet"
  subnet_ids = local.private_subnet_ids

  tags = {
    Name = "${var.project_name}-${var.environment}-db-subnet"
  }
}

resource "aws_db_parameter_group" "main" {
  name   = "${var.project_name}-${var.environment}-pg16"
  family = "postgres16"

  parameter {
    name  = "log_statement"
    value = "none"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-pg-params"
  }
}

resource "aws_db_instance" "main" {
  identifier     = "${var.project_name}-${var.environment}-postgres"
  engine         = "postgres"
  engine_version = local.postgres_engine_version

  instance_class    = var.rds_instance_class
  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = "langwatch"
  username = "langwatch"
  password = local.database_password_value

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids  = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = false
  parameter_group_name   = aws_db_parameter_group.main.name

  backup_retention_period = 7
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"

  skip_final_snapshot       = var.environment != "prod"
  final_snapshot_identifier = var.environment == "prod" ? "${var.project_name}-${var.environment}-final" : null

  tags = {
    Name = "${var.project_name}-${var.environment}-postgres"
  }
}
