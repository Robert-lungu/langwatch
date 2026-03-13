# LangWatch on AWS ECS (Terraform)

This Terraform configuration deploys LangWatch to AWS ECS Fargate with:

- **ECS Fargate** – App, Workers, LangWatch NLP, LangEvals (and optionally OpenSearch)
- **RDS PostgreSQL** – Primary database
- **ElastiCache Redis** – Queue for trace processing
- **OpenSearch Service** – Managed OpenSearch (or self-hosted in ECS)
- **ALB** – Application Load Balancer for the app
- **Service Discovery** – Internal DNS for service-to-service communication

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.5
- AWS CLI configured with appropriate credentials
- Docker (for building and pushing images to ECR)

**Images:** By default, Terraform uses **Amazon ECR** (`use_ecr = true`) to avoid Docker Hub rate limits. You must build and push images to the ECR repositories after `terraform apply`. Alternatively, set `use_ecr = false` to use public Docker Hub images (subject to rate limits).

## Quick Start

1. **Copy and configure variables:**

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your values
   ```

2. **Set required variables** (at minimum):

   - `public_url` – e.g. `https://langwatch.yourcompany.com`
   - `database_password` – Leave empty to auto-generate (stored in Secrets Manager)
   - `nextauth_secret` – Leave empty to auto-generate, or set with `openssl rand -base64 32`
   - `api_token_jwt_secret` – Same as above

3. **Initialize and apply:**

   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

4. **Push images to ECR** (when `use_ecr = true`):

   **Option A – CodeBuild (no local machine):** Syncs Docker Hub → ECR entirely in AWS:

   ```bash
   ./scripts/sync-ecr-codebuild.sh
   ```

   **Option B – Local script:** Tag and push from your machine (images must exist locally):

   ```bash
   ./scripts/push-ecr-images.sh
   ```

5. **Configure DNS:**

   Create a CNAME record pointing your domain (e.g. `langwatch.yourcompany.com`) to the ALB DNS name from the output:

   ```
   langwatch.yourcompany.com  CNAME  <alb_dns_name>
   ```

   For HTTPS, add an ACM certificate and an HTTPS listener on the ALB, or put the ALB behind CloudFront.

## Architecture

```
                    ┌─────────────────┐
                    │   Route 53      │
                    │   (optional)    │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │       ALB       │
                    └────────┬────────┘
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                   │
    ┌────▼────┐         ┌────▼────┐         ┌────▼────┐
    │   App  │         │ Workers │         │  NLP    │
    │  :5560 │         │         │         │  :5561  │
    └────┬───┘         └────┬────┘         └────┬────┘
         │                  │                   │
         │            ┌─────▼─────┐         ┌────▼────┐
         │            │ LangEvals │         │         │
         │            │  :5562    │         │         │
         │            └─────┬─────┘         └────────┘
         │                  │
         └──────────────────┼──────────────────┘
                            │
              ┌─────────────┼─────────────┐
              │             │             │
         ┌────▼────┐   ┌────▼────┐   ┌────▼────────┐
         │   RDS   │   │ Redis   │   │  OpenSearch │
         │Postgres │   │ElastiC. │   │  (managed)  │
         └─────────┘   └─────────┘   └─────────────┘
```

## Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `aws_region` | AWS region | `us-east-1` |
| `environment` | Environment name | `prod` |
| `use_ecr` | Use ECR for images (avoids Docker Hub rate limits) | `true` |
| `ecr_image_tag` | Tag for ECR images | `latest` |
| `public_url` | Public URL for LangWatch. Use `http://<alb_dns_name>` when testing without HTTPS (avoids `ERR_CONNECTION_REFUSED` on assets). | **Required** |
| `database_password` | PostgreSQL password | **Required** |
| `nextauth_secret` | NextAuth secret | Auto-generated if empty |
| `api_token_jwt_secret` | JWT secret | Auto-generated if empty |
| `use_managed_opensearch` | Use AWS OpenSearch Service | `true` |
| `use_existing_vpc` | Use existing VPC | `false` |

See `variables.tf` for the full list.

## Using an Existing VPC

Set:

```hcl
use_existing_vpc          = true
existing_vpc_id           = "vpc-xxxxx"
existing_private_subnet_ids = ["subnet-xxx", "subnet-yyy"]
existing_public_subnet_ids  = ["subnet-aaa", "subnet-bbb"]
```

Private subnets must have a route to a NAT Gateway for outbound internet (e.g. image pulls).

## HTTP vs HTTPS

When testing with the ALB URL directly (no custom domain), leave `public_url` empty in `terraform.tfvars` and leave `acm_certificate_arn` empty. The app will use the ALB URL automatically.

**Important for HTTP:** The public Docker image forces HTTPS (assets fail with `ERR_CONNECTION_REFUSED`). Use CodeBuild to build from source:

1. Set `build_langwatch_from_source = true` and `langwatch_github_repo_url = "https://github.com/YOUR_USERNAME/langwatch.git"` in `terraform.tfvars`
2. Run `terraform apply`
3. Push your code to GitHub: `git push origin main`
4. Run the build: `aws codebuild start-build --project-name $(terraform output -raw langwatch_build_codebuild_project) --region eu-west-1`
5. Force ECS deployment: `aws ecs update-service --cluster langwatch-prod --service langwatch-prod-app --force-new-deployment --region eu-west-1`

For production with a custom domain (e.g. `https://langwatch.islandnetworks.com`):

1. Create an ACM certificate in the same region for your domain (e.g. `langwatch.islandnetworks.com` or `*.islandnetworks.com`).
2. Set in `terraform.tfvars`:
   ```hcl
   public_url          = "https://langwatch.islandnetworks.com"
   acm_certificate_arn = "arn:aws:acm:eu-west-1:ACCOUNT:certificate/CERT_ID"
   ```
3. Run `terraform apply`. The ALB will get an HTTPS listener on 443 and HTTP will redirect to HTTPS.
4. Point DNS: CNAME `langwatch.islandnetworks.com` → ALB DNS name (see `terraform output alb_dns_name`).

## Managed OpenSearch vs Self-Hosted

- **Managed OpenSearch** (`use_managed_opensearch = true`): Uses AWS OpenSearch Service. Higher cost, production-ready, persistent storage.
- **Self-hosted** (`use_managed_opensearch = false`): Runs OpenSearch in ECS. Lower cost for dev, but data is ephemeral (lost on task restart).

For managed OpenSearch over HTTPS, the LangWatch app connects to the OpenSearch endpoint. If you enable fine-grained access control, you may need to configure IAM signing in the app.

## Outputs

After `terraform apply`:

- `alb_dns_name` – ALB DNS name for your CNAME
- `public_url` – `http://<alb_dns_name>`
- `ecs_cluster_name` – ECS cluster name
- `rds_endpoint` – PostgreSQL endpoint
- `redis_endpoint` – Redis endpoint
- `opensearch_endpoint` – OpenSearch endpoint

## Scaling

- Adjust `app_desired_count` and `workers_desired_count` in variables.
- Add `aws_appautoscaling_target` and `aws_appautoscaling_policy` for auto-scaling.

## Troubleshooting Stopped Tasks

### Find why a task stopped

1. **ECS Console:** Cluster → Workers service → **Tasks** tab → Click a stopped task → Check **Stopped reason** and **Containers** (exit code).

2. **AWS CLI:**
   ```bash
   aws ecs list-tasks --cluster langwatch-prod --service-name langwatch-prod-workers --desired-status STOPPED
   aws ecs describe-tasks --cluster langwatch-prod --tasks <task-arn>
   ```
   Look at `stoppedReason`, `containers[].exitCode`, and `containers[].reason`.

3. **Service events:** Cluster → Workers service → **Events** tab for deployment/health issues.

### Find worker logs in CloudWatch

Workers use a dedicated log group:

- **Log group:** `/ecs/langwatch-prod-workers`
- **Region:** Same as your deployment (e.g. `eu-west-1`)

Log streams are named `workers/workers/<task-id>`. If no logs appear:

- **Task failed before container start** (e.g. image pull, secrets, resources): Check ECS stopped reason and service events.
- **Container exits quickly:** Logs may not flush before the container is killed. The workers task has `stopTimeout: 120` to allow more time for flushing.

### Common exit codes

| Code | Meaning |
|------|---------|
| 0 | Normal exit |
| 1 | Application error (check logs) |
| 137 | OOM or killed (SIGKILL) |
| 139 | Segmentation fault |
| 255 | Command/entrypoint failure |

### Force a new deployment

```bash
aws ecs update-service --cluster langwatch-prod --service langwatch-prod-workers --force-new-deployment
```

## Cost Considerations

- **RDS** `db.t3.micro` – ~$15/month
- **ElastiCache** `cache.t3.micro` – ~$12/month
- **OpenSearch** `t3.small.search` – ~$30/month
- **ECS Fargate** – Depends on vCPU/memory and task count
- **ALB** – ~$20/month
- **NAT Gateway** – ~$35/month (when creating a new VPC)

Use `use_managed_opensearch = false` and smaller instance types for dev to reduce cost.
