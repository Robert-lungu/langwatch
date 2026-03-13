# -----------------------------------------------------------------------------
# CodeBuild - Sync Docker Hub images to ECR (no local machine needed)
# Run: aws codebuild start-build --project-name <output ecr_sync_codebuild_project>
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "codebuild_ecr_sync" {
  count = var.use_ecr ? 1 : 0

  name              = "/aws/codebuild/${var.project_name}-${var.environment}-ecr-sync"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-${var.environment}-ecr-sync-logs"
  }
}

resource "aws_codebuild_project" "ecr_sync" {
  count = var.use_ecr ? 1 : 0

  name          = "${var.project_name}-${var.environment}-ecr-sync"
  description   = "Pull images from Docker Hub and push to ECR"
  build_timeout = 30
  service_role  = aws_iam_role.codebuild_ecr_sync[0].arn

  artifacts {
    type = "NO_ARTIFACTS"
  }

  source {
    type      = "NO_SOURCE"
    buildspec = <<-BUILDSPEC
      version: 0.2
      env:
        variables:
          ECR_LANGWATCH_URL: "${aws_ecr_repository.langwatch.repository_url}"
          ECR_LANGWATCH_NLP_URL: "${aws_ecr_repository.langwatch_nlp.repository_url}"
          ECR_LANGEVALS_URL: "${aws_ecr_repository.langevals.repository_url}"
          ECR_OPENSEARCH_URL: "${var.use_managed_opensearch ? "" : aws_ecr_repository.opensearch[0].repository_url}"
          ECR_REGISTRY: "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com"
          IMAGE_TAG: "${var.ecr_image_tag}"
      phases:
        pre_build:
          commands:
            - echo "Logging in to Amazon ECR..."
            - aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY
        build:
          commands:
            - echo "Pulling from Docker Hub and pushing to ECR..."
            - |
              docker pull langwatch/langwatch:$IMAGE_TAG
              docker tag langwatch/langwatch:$IMAGE_TAG $ECR_LANGWATCH_URL:$IMAGE_TAG
              docker push $ECR_LANGWATCH_URL:$IMAGE_TAG
            - |
              docker pull langwatch/langwatch_nlp:$IMAGE_TAG
              docker tag langwatch/langwatch_nlp:$IMAGE_TAG $ECR_LANGWATCH_NLP_URL:$IMAGE_TAG
              docker push $ECR_LANGWATCH_NLP_URL:$IMAGE_TAG
            - |
              docker pull langwatch/langevals:$IMAGE_TAG
              docker tag langwatch/langevals:$IMAGE_TAG $ECR_LANGEVALS_URL:$IMAGE_TAG
              docker push $ECR_LANGEVALS_URL:$IMAGE_TAG
            - |
              if [ -n "$ECR_OPENSEARCH_URL" ]; then
                docker pull langwatch/opensearch-lite:$IMAGE_TAG
                docker tag langwatch/opensearch-lite:$IMAGE_TAG $ECR_OPENSEARCH_URL:$IMAGE_TAG
                docker push $ECR_OPENSEARCH_URL:$IMAGE_TAG
              else
                echo "Skipping opensearch-lite (use_managed_opensearch = true)"
              fi
      artifacts:
        files: []
    BUILDSPEC
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true
  }

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.codebuild_ecr_sync[0].name
      stream_name = "build"
    }
  }

  depends_on = [aws_cloudwatch_log_group.codebuild_ecr_sync]

  tags = {
    Name = "${var.project_name}-${var.environment}-ecr-sync"
  }
}

# -----------------------------------------------------------------------------
# CodeBuild - Build LangWatch from source (HTTP support) + sync other images
# Requires: build_langwatch_from_source = true, push code to CodeCommit first
# Run: aws codebuild start-build --project-name <output langwatch_build_codebuild_project>
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "codebuild_langwatch_build" {
  count = var.use_ecr && var.build_langwatch_from_source ? 1 : 0

  name              = "/aws/codebuild/${var.project_name}-${var.environment}-langwatch-build"
  retention_in_days  = 7

  tags = {
    Name = "${var.project_name}-${var.environment}-langwatch-build-logs"
  }
}

resource "aws_codebuild_project" "langwatch_build" {
  count = var.use_ecr && var.build_langwatch_from_source ? 1 : 0

  name          = "${var.project_name}-${var.environment}-langwatch-build"
  description   = "Build LangWatch from source (HTTP support) and sync other images to ECR"
  build_timeout = 60
  service_role  = aws_iam_role.codebuild_langwatch_build[0].arn

  artifacts {
    type = "NO_ARTIFACTS"
  }

  source {
    type                = "CODECOMMIT"
    location            = aws_codecommit_repository.langwatch[0].clone_url_http
    git_clone_depth     = 1
    report_build_status = false
    buildspec           = <<-BUILDSPEC
      version: 0.2
      env:
        variables:
          ECR_LANGWATCH_URL: "${aws_ecr_repository.langwatch.repository_url}"
          ECR_LANGWATCH_NLP_URL: "${aws_ecr_repository.langwatch_nlp.repository_url}"
          ECR_LANGEVALS_URL: "${aws_ecr_repository.langevals.repository_url}"
          ECR_OPENSEARCH_URL: "${var.use_managed_opensearch ? "" : aws_ecr_repository.opensearch[0].repository_url}"
          ECR_REGISTRY: "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com"
          IMAGE_TAG: "${var.ecr_image_tag}"
      phases:
        pre_build:
          commands:
            - echo "Logging in to Amazon ECR..."
            - aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY
        build:
          commands:
            - echo "Building LangWatch from source..."
            - docker build -t $ECR_LANGWATCH_URL:$IMAGE_TAG -f Dockerfile .
            - docker push $ECR_LANGWATCH_URL:$IMAGE_TAG
            - echo "Syncing other images from Docker Hub..."
            - |
              docker pull langwatch/langwatch_nlp:$IMAGE_TAG
              docker tag langwatch/langwatch_nlp:$IMAGE_TAG $ECR_LANGWATCH_NLP_URL:$IMAGE_TAG
              docker push $ECR_LANGWATCH_NLP_URL:$IMAGE_TAG
            - |
              docker pull langwatch/langevals:$IMAGE_TAG
              docker tag langwatch/langevals:$IMAGE_TAG $ECR_LANGEVALS_URL:$IMAGE_TAG
              docker push $ECR_LANGEVALS_URL:$IMAGE_TAG
            - |
              if [ -n "$ECR_OPENSEARCH_URL" ]; then
                docker pull langwatch/opensearch-lite:$IMAGE_TAG
                docker tag langwatch/opensearch-lite:$IMAGE_TAG $ECR_OPENSEARCH_URL:$IMAGE_TAG
                docker push $ECR_OPENSEARCH_URL:$IMAGE_TAG
              else
                echo "Skipping opensearch-lite (use_managed_opensearch = true)"
              fi
      artifacts:
        files: []
    BUILDSPEC
  }

  environment {
    compute_type                = "BUILD_GENERAL1_LARGE"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true
  }

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.codebuild_langwatch_build[0].name
      stream_name = "build"
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.codebuild_langwatch_build,
    aws_codecommit_repository.langwatch
  ]

  tags = {
    Name = "${var.project_name}-${var.environment}-langwatch-build"
  }
}
