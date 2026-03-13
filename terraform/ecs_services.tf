# -----------------------------------------------------------------------------
# ECS Services
# -----------------------------------------------------------------------------

resource "aws_ecs_service" "app" {
  name            = "${var.project_name}-${var.environment}-app"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.app_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = local.private_subnet_ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name  = "app"
    container_port  = 5560
  }

  service_registries {
    registry_arn = aws_service_discovery_service.app.arn
  }

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent        = 200

  depends_on = [
    aws_lb_target_group.app,
    aws_db_instance.main,
    aws_elasticache_replication_group.main
  ]
}

resource "aws_ecs_service" "workers" {
  name            = "${var.project_name}-${var.environment}-workers"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.workers.arn
  desired_count   = var.workers_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = local.private_subnet_ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent        = 200

  depends_on = [
    aws_db_instance.main,
    aws_elasticache_replication_group.main
  ]
}

resource "aws_ecs_service" "langwatch_nlp" {
  name            = "${var.project_name}-${var.environment}-langwatch-nlp"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.langwatch_nlp.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = local.private_subnet_ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.langwatch_nlp.arn
  }

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent        = 200
}

resource "aws_ecs_service" "langevals" {
  name            = "${var.project_name}-${var.environment}-langevals"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.langevals.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = local.private_subnet_ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.langevals.arn
  }

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent        = 200
}

resource "aws_ecs_service" "opensearch" {
  count = var.use_managed_opensearch ? 0 : 1

  name            = "${var.project_name}-${var.environment}-opensearch"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.opensearch[0].arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = local.private_subnet_ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.opensearch[0].arn
  }

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent        = 200
}
