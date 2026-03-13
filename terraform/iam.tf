# -----------------------------------------------------------------------------
# IAM Roles for ECS
# -----------------------------------------------------------------------------

resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.project_name}-${var.environment}-ecs-task-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-ecs-task-execution"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Allow ECS to pull images from ECR (when use_ecr = true)
resource "aws_iam_role_policy" "ecs_task_execution_ecr" {
  count = var.use_ecr ? 1 : 0

  name   = "${var.project_name}-${var.environment}-ecs-ecr"
  role   = aws_iam_role.ecs_task_execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = concat(
          [
            aws_ecr_repository.langwatch.arn,
            aws_ecr_repository.langwatch_nlp.arn,
            aws_ecr_repository.langevals.arn
          ],
          var.use_managed_opensearch ? [] : [aws_ecr_repository.opensearch[0].arn]
        )
      }
    ]
  })
}

# Allow ECS to read secrets from Secrets Manager
resource "aws_iam_role_policy" "ecs_task_execution_secrets" {
  name = "${var.project_name}-${var.environment}-ecs-secrets"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [aws_secretsmanager_secret.nextauth_secret.arn, aws_secretsmanager_secret.jwt_secret.arn]
      }
    ]
  })
}

resource "aws_iam_role" "ecs_task" {
  name = "${var.project_name}-${var.environment}-ecs-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-ecs-task"
  }
}

# -----------------------------------------------------------------------------
# CodeBuild IAM Role (when use_ecr = true)
# -----------------------------------------------------------------------------
resource "aws_iam_role" "codebuild_ecr_sync" {
  count = var.use_ecr ? 1 : 0

  name = "${var.project_name}-${var.environment}-codebuild-ecr-sync"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-codebuild-ecr-sync"
  }
}

resource "aws_iam_role_policy" "codebuild_ecr_sync" {
  count = var.use_ecr ? 1 : 0

  name   = "${var.project_name}-${var.environment}-codebuild-ecr-sync"
  role   = aws_iam_role.codebuild_ecr_sync[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = concat(
          [
            aws_ecr_repository.langwatch.arn,
            aws_ecr_repository.langwatch_nlp.arn,
            aws_ecr_repository.langevals.arn
          ],
          var.use_managed_opensearch ? [] : [aws_ecr_repository.opensearch[0].arn]
        )
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.codebuild_ecr_sync[0].arn}:*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# CodeBuild IAM Role - Build LangWatch from source (when build_langwatch_from_source = true)
# -----------------------------------------------------------------------------
resource "aws_iam_role" "codebuild_langwatch_build" {
  count = var.use_ecr && var.build_langwatch_from_source ? 1 : 0

  name = "${var.project_name}-${var.environment}-codebuild-langwatch-build"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-codebuild-langwatch-build"
  }
}

resource "aws_iam_role_policy" "codebuild_langwatch_build" {
  count = var.use_ecr && var.build_langwatch_from_source ? 1 : 0

  name   = "${var.project_name}-${var.environment}-codebuild-langwatch-build"
  role   = aws_iam_role.codebuild_langwatch_build[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = concat(
          [
            aws_ecr_repository.langwatch.arn,
            aws_ecr_repository.langwatch_nlp.arn,
            aws_ecr_repository.langevals.arn
          ],
          var.use_managed_opensearch ? [] : [aws_ecr_repository.opensearch[0].arn]
        )
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.codebuild_langwatch_build[0].arn}:*"
      }
    ]
  })
}

# ECS task role - minimal permissions for pulling public images
# Add S3, Secrets Manager etc. as needed
resource "aws_iam_role_policy" "ecs_task" {
  name = "${var.project_name}-${var.environment}-ecs-task-policy"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = [
          "${aws_cloudwatch_log_group.ecs.arn}:*",
          "${aws_cloudwatch_log_group.ecs_workers.arn}:*"
        ]
      }
    ]
  })
}
