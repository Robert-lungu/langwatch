# -----------------------------------------------------------------------------
# ElastiCache Redis
# -----------------------------------------------------------------------------

resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.project_name}-${var.environment}-redis-subnet"
  subnet_ids = local.private_subnet_ids

  tags = {
    Name = "${var.project_name}-${var.environment}-redis-subnet"
  }
}

resource "aws_elasticache_parameter_group" "main" {
  name   = "${var.project_name}-${var.environment}-redis7"
  family = "redis7"

  tags = {
    Name = "${var.project_name}-${var.environment}-redis-params"
  }
}

resource "aws_elasticache_replication_group" "main" {
  replication_group_id = "${var.project_name}-${var.environment}-redis"
  description         = "Redis for LangWatch"

  node_type            = var.elasticache_node_type
  num_cache_clusters   = 1
  parameter_group_name = aws_elasticache_parameter_group.main.name
  port                 = 6379

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.elasticache.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = length(var.redis_auth_token) > 0
  auth_token                 = length(var.redis_auth_token) > 0 ? var.redis_auth_token : null

  automatic_failover_enabled = false
  multi_az_enabled          = false

  tags = {
    Name = "${var.project_name}-${var.environment}-redis"
  }
}
