# -----------------------------------------------------------------------------
# Secrets Manager - Store sensitive values
# -----------------------------------------------------------------------------

resource "random_password" "nextauth" {
  count = var.nextauth_secret == "" ? 1 : 0

  length  = 32
  special = true
}

resource "random_password" "jwt" {
  count = var.api_token_jwt_secret == "" ? 1 : 0

  length  = 32
  special = true
}

resource "random_password" "database" {
  count = var.database_password == "" ? 1 : 0

  length  = 32
  special = true
  override_special = "!#$%&*()-_=+[]{}<>:?" # Excludes @ : / to avoid URL parsing issues in DATABASE_URL
}

locals {
  nextauth_secret_value   = var.nextauth_secret != "" ? var.nextauth_secret : random_password.nextauth[0].result
  jwt_secret_value        = var.api_token_jwt_secret != "" ? var.api_token_jwt_secret : random_password.jwt[0].result
  database_password_value = var.database_password != "" ? var.database_password : random_password.database[0].result
}

resource "aws_secretsmanager_secret" "nextauth_secret" {
  name        = "${var.project_name}/${var.environment}/nextauth-secret"
  description = "NextAuth secret for LangWatch"

  tags = {
    Name = "${var.project_name}-${var.environment}-nextauth-secret"
  }
}

resource "aws_secretsmanager_secret_version" "nextauth_secret" {
  secret_id     = aws_secretsmanager_secret.nextauth_secret.id
  secret_string = local.nextauth_secret_value
}

resource "aws_secretsmanager_secret" "jwt_secret" {
  name        = "${var.project_name}/${var.environment}/api-token-jwt-secret"
  description = "API token JWT secret for LangWatch"

  tags = {
    Name = "${var.project_name}-${var.environment}-jwt-secret"
  }
}

resource "aws_secretsmanager_secret_version" "jwt_secret" {
  secret_id     = aws_secretsmanager_secret.jwt_secret.id
  secret_string = local.jwt_secret_value
}

# Store database password in Secrets Manager for retrieval (e.g. backups, manual access)
resource "aws_secretsmanager_secret" "database_password" {
  name        = "${var.project_name}/${var.environment}/database-password"
  description = "RDS PostgreSQL password for LangWatch"

  tags = {
    Name = "${var.project_name}-${var.environment}-database-password"
  }
}

resource "aws_secretsmanager_secret_version" "database_password" {
  secret_id     = aws_secretsmanager_secret.database_password.id
  secret_string = local.database_password_value
}
