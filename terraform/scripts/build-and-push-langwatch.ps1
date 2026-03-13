# -----------------------------------------------------------------------------
# Build LangWatch app from source and push to ECR
# Use this when you need HTTP support (public Docker image forces HTTPS)
# Run from project root: .\terraform\scripts\build-and-push-langwatch.ps1
# Requires: terraform, aws cli, docker
# -----------------------------------------------------------------------------

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$TerraformDir = Resolve-Path (Join-Path $ScriptDir "..")
$ProjectRoot = Resolve-Path (Join-Path $TerraformDir "..")
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

Write-Host "=== Building LangWatch from source (HTTP support) ==="
Write-Host "Project root: $ProjectRoot"
Write-Host "ECR URL:     ${ecrLangwatch}:$imageTag"
Write-Host ""

# Build from source
Set-Location $ProjectRoot
docker build -t "langwatch/langwatch:$imageTag" -f Dockerfile .

if ($LASTEXITCODE -ne 0) {
  Write-Host "Build failed."
  exit 1
}

Write-Host ""
Write-Host "=== ECR Login ==="
aws ecr get-login-password --region $awsRegion | docker login --username AWS --password-stdin $ecrRegistry

Write-Host ""
Write-Host "=== Pushing to ECR ==="
docker tag "langwatch/langwatch:$imageTag" "${ecrLangwatch}:$imageTag"
docker push "${ecrLangwatch}:$imageTag"

Write-Host ""
Write-Host "=== Done ==="
$clusterName = terraform output -raw ecs_cluster_name
Write-Host "Image pushed. Force new ECS deployment:"
Write-Host "  aws ecs update-service --cluster $clusterName --service ${clusterName}-app --force-new-deployment --region $awsRegion"
