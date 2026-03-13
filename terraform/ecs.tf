# -----------------------------------------------------------------------------
# ECS Cluster and Services
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.project_name}-${var.environment}"
  retention_in_days = 14

  tags = {
    Name = "${var.project_name}-${var.environment}-logs"
  }
}

# Dedicated log group for workers - easier to find and debug
resource "aws_cloudwatch_log_group" "ecs_workers" {
  name              = "/ecs/${var.project_name}-${var.environment}-workers"
  retention_in_days = 14

  tags = {
    Name = "${var.project_name}-${var.environment}-workers-logs"
  }
}

resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-${var.environment}"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}"
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 0
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

# -----------------------------------------------------------------------------
# Task Definitions
# -----------------------------------------------------------------------------

locals {
  # Use ALB URL when public_url is empty (no custom domain)
  base_host_value = var.base_host != "" ? var.base_host : (var.public_url != "" ? var.public_url : "http://${aws_lb.main.dns_name}")
  database_url    = "postgresql://${aws_db_instance.main.username}:${local.database_password_value}@${aws_db_instance.main.address}:${aws_db_instance.main.port}/${aws_db_instance.main.db_name}"
  redis_url       = length(var.redis_auth_token) > 0 ? "redis://:${var.redis_auth_token}@${aws_elasticache_replication_group.main.primary_endpoint_address}:6379" : "redis://${aws_elasticache_replication_group.main.primary_endpoint_address}:6379"
  opensearch_url  = var.use_managed_opensearch ? "https://${aws_opensearch_domain.main[0].endpoint}" : "http://opensearch.${aws_service_discovery_private_dns_namespace.main.name}:9200"
  sd_namespace    = aws_service_discovery_private_dns_namespace.main.name

  # ECR image URIs (used when use_ecr = true)
  ecr_registry    = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com"
  app_image_uri   = var.use_ecr ? "${aws_ecr_repository.langwatch.repository_url}:${var.ecr_image_tag}" : var.app_image
  workers_image_uri = var.use_ecr ? "${aws_ecr_repository.langwatch.repository_url}:${var.ecr_image_tag}" : var.workers_image
  nlp_image_uri   = var.use_ecr ? "${aws_ecr_repository.langwatch_nlp.repository_url}:${var.ecr_image_tag}" : var.langwatch_nlp_image
  langevals_image_uri = var.use_ecr ? "${aws_ecr_repository.langevals.repository_url}:${var.ecr_image_tag}" : var.langevals_image
  opensearch_image_uri = var.use_managed_opensearch ? var.opensearch_image : (var.use_ecr ? "${aws_ecr_repository.opensearch[0].repository_url}:${var.ecr_image_tag}" : var.opensearch_image)

  # Wait for OpenSearch before migrations when self-hosted (OpenSearch takes 1-2 min to start)
  app_start_command = var.use_managed_opensearch ? "cd langwatch && pnpm run start:prepare:db && pnpm run start:app" : "echo 'Waiting for OpenSearch...'; for i in $(seq 1 48); do curl -sf http://opensearch.${aws_service_discovery_private_dns_namespace.main.name}:9200/_cluster/health 2>/dev/null | grep -qE '\"status\":\"(green|yellow)\"' && echo 'OpenSearch ready!' && break; sleep 5; done; cd langwatch && pnpm run start:prepare:db && pnpm run start:app"
}

# Service discovery for internal service-to-service communication
resource "aws_service_discovery_private_dns_namespace" "main" {
  name        = "${var.project_name}.local"
  description = "Private DNS namespace for LangWatch services"
  vpc         = local.vpc_id
}

resource "aws_service_discovery_service" "app" {
  name = "app"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

resource "aws_service_discovery_service" "langwatch_nlp" {
  name = "langwatch-nlp"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

resource "aws_service_discovery_service" "langevals" {
  name = "langevals"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

resource "aws_service_discovery_service" "opensearch" {
  count = var.use_managed_opensearch ? 0 : 1

  name = "opensearch"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

# -----------------------------------------------------------------------------
# App Task Definition
# -----------------------------------------------------------------------------

resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project_name}-${var.environment}-app"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.app_cpu
  memory                   = var.app_memory

  execution_role_arn = aws_iam_role.ecs_task_execution.arn
  task_role_arn      = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "app"
      image     = local.app_image_uri
      essential = true

      command = ["sh", "-c", local.app_start_command]

      portMappings = [
        {
          containerPort = 5560
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "NODE_ENV", value = "production" },
        { name = "SKIP_ENV_VALIDATION", value = "true" },
        { name = "DISABLE_PII_REDACTION", value = "true" },
        { name = "DATABASE_URL", value = local.database_url },
        { name = "ELASTICSEARCH_NODE_URL", value = local.opensearch_url },
        { name = "IS_OPENSEARCH", value = "true" },
        { name = "REDIS_URL", value = local.redis_url },
        { name = "LANGWATCH_NLP_SERVICE", value = "http://langwatch-nlp.${local.sd_namespace}:5561" },
        { name = "LANGEVALS_ENDPOINT", value = "http://langevals.${local.sd_namespace}:5562" },
        { name = "INSTALL_METHOD", value = "docker" },
        { name = "BASE_HOST", value = local.base_host_value },
        { name = "NEXTAUTH_URL", value = local.base_host_value }
      ]

      secrets = [
        { name = "NEXTAUTH_SECRET", valueFrom = aws_secretsmanager_secret_version.nextauth_secret.arn },
        { name = "API_TOKEN_JWT_SECRET", valueFrom = aws_secretsmanager_secret_version.jwt_secret.arn }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"       = var.aws_region
          "awslogs-stream-prefix" = "app"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:5560/ || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 300
      }
    }
  ])
}

# -----------------------------------------------------------------------------
# Workers Task Definition
# -----------------------------------------------------------------------------

resource "aws_ecs_task_definition" "workers" {
  family                   = "${var.project_name}-${var.environment}-workers"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.workers_cpu
  memory                   = var.workers_memory

  execution_role_arn = aws_iam_role.ecs_task_execution.arn
  task_role_arn      = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "workers"
      image     = local.workers_image_uri
      essential = true
      stopTimeout = 120

      command = ["sh", "-c", "cd langwatch && pnpm run start:workers"]

      environment = [
        { name = "NODE_ENV", value = "production" },
        { name = "ENVIRONMENT", value = var.environment },
        { name = "SKIP_ENV_VALIDATION", value = "true" },
        { name = "DATABASE_URL", value = local.database_url },
        { name = "ELASTICSEARCH_NODE_URL", value = local.opensearch_url },
        { name = "IS_OPENSEARCH", value = "true" },
        { name = "REDIS_URL", value = local.redis_url },
        { name = "LANGWATCH_NLP_SERVICE", value = "http://langwatch-nlp.${local.sd_namespace}:5561" },
        { name = "LANGEVALS_ENDPOINT", value = "http://langevals.${local.sd_namespace}:5562" },
        { name = "BASE_HOST", value = local.base_host_value },
        { name = "NEXTAUTH_URL", value = local.base_host_value }
      ]

      secrets = [
        { name = "API_TOKEN_JWT_SECRET", valueFrom = aws_secretsmanager_secret_version.jwt_secret.arn },
        { name = "NEXTAUTH_SECRET", valueFrom = aws_secretsmanager_secret_version.nextauth_secret.arn }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_workers.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "workers"
        }
      }
    }
  ])
}

# -----------------------------------------------------------------------------
# LangWatch NLP Task Definition
# -----------------------------------------------------------------------------

resource "aws_ecs_task_definition" "langwatch_nlp" {
  family                   = "${var.project_name}-${var.environment}-langwatch-nlp"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 512
  memory                   = 1024

  execution_role_arn = aws_iam_role.ecs_task_execution.arn
  task_role_arn      = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "langwatch-nlp"
      image     = local.nlp_image_uri
      essential = true

      portMappings = [
        {
          containerPort = 5561
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "LANGWATCH_ENDPOINT", value = "http://app.${local.sd_namespace}:5560" }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"       = var.aws_region
          "awslogs-stream-prefix" = "langwatch-nlp"
        }
      }
    }
  ])
}

# -----------------------------------------------------------------------------
# LangEvals Task Definition
# -----------------------------------------------------------------------------

resource "aws_ecs_task_definition" "langevals" {
  family                   = "${var.project_name}-${var.environment}-langevals"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 512
  memory                   = 2048 # Fargate requires 1024|2048|3072|4096 for 512 CPU

  execution_role_arn = aws_iam_role.ecs_task_execution.arn
  task_role_arn      = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "langevals"
      image     = local.langevals_image_uri
      essential = true

      portMappings = [
        {
          containerPort = 5562
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "DISABLE_EVALUATORS_PRELOAD", value = "true" }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"       = var.aws_region
          "awslogs-stream-prefix" = "langevals"
        }
      }
    }
  ])
}

# -----------------------------------------------------------------------------
# OpenSearch Task Definition (when not using managed OpenSearch)
# -----------------------------------------------------------------------------

resource "aws_ecs_task_definition" "opensearch" {
  count = var.use_managed_opensearch ? 0 : 1

  family                   = "${var.project_name}-${var.environment}-opensearch"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 1024
  memory                   = 2048

  execution_role_arn = aws_iam_role.ecs_task_execution.arn
  task_role_arn      = aws_iam_role.ecs_task.arn

  # Note: OpenSearch data is ephemeral in Fargate. For production, use use_managed_opensearch = true
  container_definitions = jsonencode([
    {
      name      = "opensearch"
      image     = local.opensearch_image_uri
      essential = true

      portMappings = [
        { containerPort = 9200, protocol = "tcp" },
        { containerPort = 9600, protocol = "tcp" }
      ]

      environment = [
        { name = "discovery.type", value = "single-node" },
        { name = "DISABLE_SECURITY_PLUGIN", value = "true" },
        { name = "OPENSEARCH_JAVA_OPTS", value = "-Xms512m -Xmx512m -XX:+UseG1GC" },
        { name = "cluster.routing.allocation.disk.threshold_enabled", value = "false" },
        { name = "bootstrap.memory_lock", value = "false" },
        { name = "node.store.allow_mmap", value = "false" }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"       = var.aws_region
          "awslogs-stream-prefix" = "opensearch"
        }
      }
    }
  ])
}
