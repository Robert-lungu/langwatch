# Sync Docker Hub images to ECR via CodeBuild (no local Docker needed)
# Run from terraform directory: .\scripts\sync-ecr-codebuild.ps1

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location (Join-Path $ScriptDir "..")

$project = terraform output -raw ecr_sync_codebuild_project 2>$null
if ([string]::IsNullOrEmpty($project) -or $project -eq "null") {
  Write-Host "Error: Run 'terraform apply' first. Ensure use_ecr = true."
  exit 1
}

$region = terraform output -raw aws_region 2>$null
Write-Host "Starting CodeBuild: $project (region: $region)"
aws codebuild start-build --project-name $project --region $region
Write-Host "Build started. Check AWS Console: CodeBuild → $project → Build history"
