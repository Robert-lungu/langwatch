#!/bin/bash
# -----------------------------------------------------------------------------
# Build LangWatch app from source and push to ECR
# Use this when you need HTTP support (public Docker image forces HTTPS)
# Run from project root: ./terraform/scripts/build-and-push-langwatch.sh
# Requires: terraform, aws cli, docker
# -----------------------------------------------------------------------------

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$TERRAFORM_DIR/.." && pwd)"
cd "$TERRAFORM_DIR"

# Check terraform is initialized
ecrLangwatch=$(terraform output -raw ecr_langwatch_url 2>/dev/null || true)
if [ -z "$ecrLangwatch" ] || [ "$ecrLangwatch" = "null" ]; then
  echo "Error: Run 'terraform init' and 'terraform apply' first."
  echo "Ensure use_ecr = true in terraform.tfvars"
  exit 1
fi

ecrRegistry="${ecrLangwatch%%/*}"
awsRegion=$(terraform output -raw aws_region 2>/dev/null || echo "eu-west-1")
imageTag="${IMAGE_TAG:-latest}"

echo "=== Building LangWatch from source (HTTP support) ==="
echo "Project root: $PROJECT_ROOT"
echo "ECR URL:     ${ecrLangwatch}:${imageTag}"
echo ""

# Build from source
cd "$PROJECT_ROOT"
docker build -t "langwatch/langwatch:$imageTag" -f Dockerfile .

echo ""
echo "=== ECR Login ==="
aws ecr get-login-password --region "$awsRegion" | docker login --username AWS --password-stdin "$ecrRegistry"

echo ""
echo "=== Pushing to ECR ==="
docker tag "langwatch/langwatch:$imageTag" "${ecrLangwatch}:${imageTag}"
docker push "${ecrLangwatch}:${imageTag}"

echo ""
echo "=== Done ==="
clusterName=$(terraform output -raw ecs_cluster_name)
echo "Image pushed. Force new ECS deployment:"
echo "  aws ecs update-service --cluster $clusterName --service ${clusterName}-app --force-new-deployment --region $awsRegion"
