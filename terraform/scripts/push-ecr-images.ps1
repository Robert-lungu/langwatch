# -----------------------------------------------------------------------------
# Push LangWatch images to Amazon ECR (uses local images only)
# Run from the terraform directory: .\scripts\push-ecr-images.ps1
# Requires: terraform, aws cli, docker
# Ensure images exist locally before running (e.g. docker pull langwatch/langwatch:latest)
# -----------------------------------------------------------------------------

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$TerraformDir = Resolve-Path (Join-Path $ScriptDir "..")
Set-Location $TerraformDir

# Check terraform is initialized
try {
  $ecrLangwatch = terraform output -raw ecr_langwatch_url 2>$null
} catch {
  Write-Host "Error: Run 'terraform init' and 'terraform apply' first."
  Write-Host "Ensure use_ecr = true in terraform.tfvars"
  exit 1
}

if ([string]::IsNullOrEmpty($ecrLangwatch) -or $ecrLangwatch -eq "null") {
  Write-Host "Error: ECR not configured. Set use_ecr = true and run terraform apply."
  exit 1
}

$ecrRegistry = ($ecrLangwatch -split "/")[0]
$awsRegion = if ($ecrRegistry -match "\.dkr\.ecr\.([^.]+)\.amazonaws\.com") { $Matches[1] } else { "eu-west-1" }
$imageTag = if ($env:IMAGE_TAG) { $env:IMAGE_TAG } else { "latest" }

Write-Host "=== ECR Login ==="
Write-Host "Registry: $ecrRegistry"
Write-Host "Region:   $awsRegion"
Write-Host "Tag:      $imageTag"
Write-Host ""

aws ecr get-login-password --region $awsRegion | docker login --username AWS --password-stdin $ecrRegistry

Write-Host ""
Write-Host "=== Tagging and pushing images ==="

# LangWatch (app + workers)
Write-Host "[1/3] langwatch..."
$langwatchUrl = terraform output -raw ecr_langwatch_url
docker tag "langwatch/langwatch:$imageTag" "${langwatchUrl}:$imageTag"
docker push "${langwatchUrl}:$imageTag"

# LangWatch NLP
Write-Host "[2/3] langwatch_nlp..."
$nlpUrl = terraform output -raw ecr_langwatch_nlp_url
docker tag "langwatch/langwatch_nlp:$imageTag" "${nlpUrl}:$imageTag"
docker push "${nlpUrl}:$imageTag"

# LangEvals
Write-Host "[3/3] langevals..."
$langevalsUrl = terraform output -raw ecr_langevals_url
docker tag "langwatch/langevals:$imageTag" "${langevalsUrl}:$imageTag"
docker push "${langevalsUrl}:$imageTag"

# OpenSearch (only when use_managed_opensearch = false)
try {
  $ecrOpenSearch = terraform output -raw ecr_opensearch_url 2>$null
} catch {
  $ecrOpenSearch = $null
}

if (-not [string]::IsNullOrEmpty($ecrOpenSearch) -and $ecrOpenSearch -ne "null") {
  Write-Host "[4/4] opensearch-lite..."
  docker tag "langwatch/opensearch-lite:$imageTag" "${ecrOpenSearch}:$imageTag"
  docker push "${ecrOpenSearch}:$imageTag"
} else {
  Write-Host "[4/4] opensearch-lite skipped (use_managed_opensearch = true)"
}

Write-Host ""
Write-Host "=== Done ==="
$clusterName = terraform output -raw ecs_cluster_name
Write-Host "Images pushed. Force new ECS deployment to use them:"
Write-Host "  aws ecs update-service --cluster $clusterName --service <service-name> --force-new-deployment --region $awsRegion"
