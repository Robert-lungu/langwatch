# -----------------------------------------------------------------------------
# CodeCommit - Repository for LangWatch source (used by CodeBuild)
# Push your code here, then run the langwatch-build CodeBuild project
# -----------------------------------------------------------------------------

resource "aws_codecommit_repository" "langwatch" {
  count = var.use_ecr && var.build_langwatch_from_source ? 1 : 0

  repository_name = "${var.project_name}-${var.environment}-langwatch"
  description     = "LangWatch source for CodeBuild (build from source for HTTP support)"

  tags = {
    Name = "${var.project_name}-${var.environment}-langwatch"
  }
}
