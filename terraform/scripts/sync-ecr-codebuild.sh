#!/usr/bin/env bash
# Sync Docker Hub images to ECR via CodeBuild (no local Docker needed)
# Run from terraform directory: ./scripts/sync-ecr-codebuild.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$(dirname "$SCRIPT_DIR")"

PROJECT=$(terraform output -raw ecr_sync_codebuild_project 2>/dev/null) || true
if [ -z "$PROJECT" ] || [ "$PROJECT" = "null" ]; then
  echo "Error: Run 'terraform apply' first. Ensure use_ecr = true."
  exit 1
fi

REGION=$(terraform output -raw aws_region 2>/dev/null || true)
echo "Starting CodeBuild: $PROJECT (region: $REGION)"
aws codebuild start-build --project-name "$PROJECT" --region "$REGION"
echo "Build started. Check AWS Console: CodeBuild → $PROJECT → Build history"
