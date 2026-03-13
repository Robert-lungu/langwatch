variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "langwatch"
}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "use_existing_vpc" {
  description = "Use existing VPC instead of creating new one"
  type        = bool
  default     = false
}

variable "existing_vpc_id" {
  description = "Existing VPC ID (required when use_existing_vpc = true)"
  type        = string
  default     = ""
}

variable "existing_private_subnet_ids" {
  description = "Existing private subnet IDs for ECS (required when use_existing_vpc = true)"
  type        = list(string)
  default     = []
}

variable "existing_public_subnet_ids" {
  description = "Existing public subnet IDs for ALB (required when use_existing_vpc = true)"
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# Application
# -----------------------------------------------------------------------------
variable "use_ecr" {
  description = "Use Amazon ECR for container images (recommended - avoids Docker Hub rate limits)"
  type        = bool
  default     = true
}

variable "app_image" {
  description = "Docker image for LangWatch app (used when use_ecr = false)"
  type        = string
  default     = "langwatch/langwatch:latest"
}

variable "workers_image" {
  description = "Docker image for LangWatch workers (used when use_ecr = false)"
  type        = string
  default     = "langwatch/langwatch:latest"
}

variable "langwatch_nlp_image" {
  description = "Docker image for LangWatch NLP service (used when use_ecr = false)"
  type        = string
  default     = "langwatch/langwatch_nlp:latest"
}

variable "langevals_image" {
  description = "Docker image for LangEvals service (used when use_ecr = false)"
  type        = string
  default     = "langwatch/langevals:latest"
}

variable "opensearch_image" {
  description = "Docker image for OpenSearch when use_managed_opensearch = false (used when use_ecr = false)"
  type        = string
  default     = "langwatch/opensearch-lite:latest"
}

variable "ecr_image_tag" {
  description = "Tag for ECR images (e.g. latest, v1.0.0)"
  type        = string
  default     = "latest"
}

variable "build_langwatch_from_source" {
  description = "Build LangWatch app from source via CodeBuild (enables HTTP support). Uses GitHub repo."
  type        = bool
  default     = false
}

variable "langwatch_github_repo_url" {
  description = "GitHub repo URL for LangWatch source (e.g. https://github.com/Robert-lungu/langwatch.git)"
  type        = string
  default     = "https://github.com/Robert-lungu/langwatch.git"
}

variable "public_url" {
  description = "Public URL for LangWatch. Leave empty to use ALB URL (http://<alb_dns_name>). Set for custom domain (e.g. https://langwatch.example.com)"
  type        = string
  default     = ""
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for HTTPS (required for custom domain, e.g. https://langwatch.islandnetworks.com)"
  type        = string
  default     = ""
}

variable "base_host" {
  description = "Base host URL (usually same as public_url)"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Secrets (pass via TF_VAR_ or terraform.tfvars - never commit!)
# -----------------------------------------------------------------------------
variable "nextauth_secret" {
  description = "NextAuth secret for session encryption (leave empty to auto-generate)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "api_token_jwt_secret" {
  description = "JWT secret for API token generation (leave empty to auto-generate)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "credentials_encryption_key" {
  description = "32-byte hex string for credentials encryption"
  type        = string
  sensitive   = true
  default     = ""
}

variable "database_password" {
  description = "PostgreSQL database password (leave empty to auto-generate with random provider)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "redis_auth_token" {
  description = "Redis AUTH token (leave empty for no auth when using ElastiCache)"
  type        = string
  sensitive   = true
  default     = ""
}

# -----------------------------------------------------------------------------
# Data Services
# -----------------------------------------------------------------------------
variable "use_managed_opensearch" {
  description = "Use AWS OpenSearch Service. Set to false for self-hosted OpenSearch in ECS (recommended - LangWatch client lacks AWS SigV4 support for managed OpenSearch)"
  type        = bool
  default     = false
}

variable "opensearch_instance_type" {
  description = "OpenSearch instance type (when use_managed_opensearch = true)"
  type        = string
  default     = "t3.small.search"
}

variable "opensearch_instance_count" {
  description = "Number of OpenSearch instances"
  type        = number
  default     = 1
}

variable "rds_instance_class" {
  description = "RDS instance class for PostgreSQL"
  type        = string
  default     = "db.t3.micro"
}

variable "rds_engine_version" {
  description = "PostgreSQL engine version (e.g. 16.1). Leave empty to use latest 16.x from data source. Override if data source fails in your region."
  type        = string
  default     = ""
}

variable "elasticache_node_type" {
  description = "ElastiCache node type for Redis"
  type        = string
  default     = "cache.t3.micro"
}

# -----------------------------------------------------------------------------
# ECS
# -----------------------------------------------------------------------------
variable "app_cpu" {
  description = "CPU units for app task (1024 = 1 vCPU)"
  type        = number
  default     = 512
}

variable "app_memory" {
  description = "Memory in MB for app task (2048 recommended for migrations + OpenSearch)"
  type        = number
  default     = 2048
}

variable "workers_cpu" {
  description = "CPU units for workers task"
  type        = number
  default     = 512
}

variable "workers_memory" {
  description = "Memory in MB for workers task"
  type        = number
  default     = 1024
}

variable "workers_desired_count" {
  description = "Desired number of worker tasks"
  type        = number
  default     = 1
}

variable "app_desired_count" {
  description = "Desired number of app tasks"
  type        = number
  default     = 1
}

variable "app_health_check_grace_period_seconds" {
  description = "Grace period (seconds) before ALB health checks count against the app service. App startup (OpenSearch wait, migrations, Next.js) can take 5+ minutes."
  type        = number
  default     = 600
}
