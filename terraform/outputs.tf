# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the ALB (for Route53 alias records)"
  value       = aws_lb.main.zone_id
}

output "public_url" {
  description = "URL to access LangWatch (ALB URL when public_url is empty, else custom domain)"
  value       = local.base_host_value
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = aws_db_instance.main.address
}

output "redis_endpoint" {
  description = "ElastiCache Redis primary endpoint"
  value       = aws_elasticache_replication_group.main.primary_endpoint_address
}

output "database_password_secret_arn" {
  description = "Secrets Manager ARN for the database password (retrieve with: aws secretsmanager get-secret-value --secret-id <arn>)"
  value       = aws_secretsmanager_secret.database_password.arn
  sensitive   = true
}

output "opensearch_endpoint" {
  description = "OpenSearch endpoint (HTTPS for managed, HTTP for self-hosted)"
  value       = var.use_managed_opensearch ? "https://${aws_opensearch_domain.main[0].endpoint}" : "http://opensearch.${aws_service_discovery_private_dns_namespace.main.name}:9200"
}

output "vpc_id" {
  description = "VPC ID"
  value       = local.vpc_id
}

output "aws_region" {
  description = "AWS region used for deployment"
  value       = data.aws_region.current.name
}

# -----------------------------------------------------------------------------
# ECR (when use_ecr = true)
# -----------------------------------------------------------------------------
output "ecr_langwatch_url" {
  description = "ECR repository URL for LangWatch app/workers - push images here"
  value       = var.use_ecr ? aws_ecr_repository.langwatch.repository_url : null
}

output "ecr_langwatch_nlp_url" {
  description = "ECR repository URL for LangWatch NLP - push images here"
  value       = var.use_ecr ? aws_ecr_repository.langwatch_nlp.repository_url : null
}

output "ecr_langevals_url" {
  description = "ECR repository URL for LangEvals - push images here"
  value       = var.use_ecr ? aws_ecr_repository.langevals.repository_url : null
}

output "ecr_opensearch_url" {
  description = "ECR repository URL for OpenSearch - push images here (when use_managed_opensearch = false)"
  value       = var.use_ecr && !var.use_managed_opensearch ? aws_ecr_repository.opensearch[0].repository_url : null
}

# -----------------------------------------------------------------------------
# CodeBuild (when use_ecr = true) - sync Docker Hub to ECR without local machine
# -----------------------------------------------------------------------------
output "ecr_sync_codebuild_project" {
  description = "CodeBuild project name - run to sync Docker Hub images to ECR (no local machine needed)"
  value       = var.use_ecr ? aws_codebuild_project.ecr_sync[0].name : null
}

output "ecr_sync_command" {
  description = "Command to sync images from Docker Hub to ECR via CodeBuild"
  value       = var.use_ecr ? "aws codebuild start-build --project-name ${aws_codebuild_project.ecr_sync[0].name} --region ${data.aws_region.current.name}" : null
}

# -----------------------------------------------------------------------------
# CodeBuild - Build LangWatch from source (when build_langwatch_from_source = true)
# -----------------------------------------------------------------------------
output "langwatch_build_codebuild_project" {
  description = "CodeBuild project to build LangWatch from source (HTTP support)"
  value       = var.use_ecr && var.build_langwatch_from_source ? aws_codebuild_project.langwatch_build[0].name : null
}

output "langwatch_build_command" {
  description = "Command to build LangWatch from source via CodeBuild"
  value       = var.use_ecr && var.build_langwatch_from_source ? "aws codebuild start-build --project-name ${aws_codebuild_project.langwatch_build[0].name} --region ${data.aws_region.current.name}" : null
}

output "langwatch_codecommit_clone_url" {
  description = "CodeCommit clone URL - push your code here before running the build"
  value       = var.use_ecr && var.build_langwatch_from_source ? aws_codecommit_repository.langwatch[0].clone_url_http : null
}
