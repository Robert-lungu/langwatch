# -----------------------------------------------------------------------------
# Amazon ECR - Container image registry (avoids Docker Hub rate limits)
# -----------------------------------------------------------------------------

resource "aws_ecr_repository" "langwatch" {
  name                 = "${var.project_name}-${var.environment}/langwatch"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-langwatch"
  }
}

resource "aws_ecr_repository" "langwatch_nlp" {
  name                 = "${var.project_name}-${var.environment}/langwatch-nlp"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-langwatch-nlp"
  }
}

resource "aws_ecr_repository" "langevals" {
  name                 = "${var.project_name}-${var.environment}/langevals"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-langevals"
  }
}

resource "aws_ecr_repository" "opensearch" {
  count = var.use_managed_opensearch ? 0 : 1

  name                 = "${var.project_name}-${var.environment}/opensearch-lite"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-opensearch-lite"
  }
}

# Lifecycle policy - keep last 10 images to avoid unbounded storage
resource "aws_ecr_lifecycle_policy" "langwatch" {
  repository = aws_ecr_repository.langwatch.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}

resource "aws_ecr_lifecycle_policy" "langwatch_nlp" {
  repository = aws_ecr_repository.langwatch_nlp.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}

resource "aws_ecr_lifecycle_policy" "langevals" {
  repository = aws_ecr_repository.langevals.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}

resource "aws_ecr_lifecycle_policy" "opensearch" {
  count = var.use_managed_opensearch ? 0 : 1

  repository = aws_ecr_repository.opensearch[0].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}
