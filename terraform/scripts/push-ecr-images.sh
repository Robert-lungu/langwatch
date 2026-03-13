#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Push LangWatch images to Amazon ECR (uses local images only)
# Run from the terraform directory: ./scripts/push-ecr-images.sh
# Requires: terraform, aws cli, docker
# Ensure images exist locally before running (e.g. docker pull langwatch/langwatch:latest)
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$TERRAFORM_DIR"

# Check terraform is initialized
if ! terraform output -raw ecr_langwatch_url &>/dev/null; then
  echo "Error: Run 'terraform init' and 'terraform apply' first."
  echo "Ensure use_ecr = true in terraform.tfvars"
  exit 1
fi

# Get ECR registry URL and region from terraform output
ECR_LANGWATCH=$(terraform output -raw ecr_langwatch_url 2>/dev/null || true)
if [ -z "$ECR_LANGWATCH" ] || [ "$ECR_LANGWATCH" = "null" ]; then
  echo "Error: ECR not configured. Set use_ecr = true and run terraform apply."
  exit 1
fi

ECR_REGISTRY=$(echo "$ECR_LANGWATCH" | cut -d'/' -f1)
# Extract region from registry URL (e.g. 123456.dkr.ecr.eu-west-1.amazonaws.com -> eu-west-1)
AWS_REGION=$(echo "$ECR_REGISTRY" | cut -d. -f4)
IMAGE_TAG="${IMAGE_TAG:-latest}"

echo "=== ECR Login ==="
echo "Registry: $ECR_REGISTRY"
echo "Region:   $AWS_REGION"
echo "Tag:      $IMAGE_TAG"
echo ""

aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin "$ECR_REGISTRY"

echo ""
echo "=== Tagging and pushing images ==="

# LangWatch (app + workers)
echo "[1/3] langwatch..."
docker tag "langwatch/langwatch:$IMAGE_TAG" "$(terraform output -raw ecr_langwatch_url):$IMAGE_TAG"
docker push "$(terraform output -raw ecr_langwatch_url):$IMAGE_TAG"

# LangWatch NLP
echo "[2/3] langwatch_nlp..."
docker tag "langwatch/langwatch_nlp:$IMAGE_TAG" "$(terraform output -raw ecr_langwatch_nlp_url):$IMAGE_TAG"
docker push "$(terraform output -raw ecr_langwatch_nlp_url):$IMAGE_TAG"

# LangEvals
echo "[3/3] langevals..."
docker tag "langwatch/langevals:$IMAGE_TAG" "$(terraform output -raw ecr_langevals_url):$IMAGE_TAG"
docker push "$(terraform output -raw ecr_langevals_url):$IMAGE_TAG"

# OpenSearch (only when use_managed_opensearch = false)
ECR_OPENSEARCH=$(terraform output -raw ecr_opensearch_url 2>/dev/null || true)
if [ -n "$ECR_OPENSEARCH" ] && [ "$ECR_OPENSEARCH" != "null" ]; then
  echo "[4/4] opensearch-lite..."
  docker tag "langwatch/opensearch-lite:$IMAGE_TAG" "$ECR_OPENSEARCH:$IMAGE_TAG"
  docker push "$ECR_OPENSEARCH:$IMAGE_TAG"
else
  echo "[4/4] opensearch-lite skipped (use_managed_opensearch = true)"
fi

echo ""
echo "=== Done ==="
echo "Images pushed. Force new ECS deployment to use them:"
echo "  aws ecs update-service --cluster \$(terraform output -raw ecs_cluster_name) --service <service-name> --force-new-deployment --region $AWS_REGION"
