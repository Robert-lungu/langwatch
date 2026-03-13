# -----------------------------------------------------------------------------
# OpenSearch Service (managed) - used when use_managed_opensearch = true
# -----------------------------------------------------------------------------

# OpenSearch requires a service-linked role to access VPC. Create it before the domain.
resource "aws_iam_service_linked_role" "opensearch" {
  count = var.use_managed_opensearch ? 1 : 0

  aws_service_name = "es.amazonaws.com"
}

resource "aws_opensearch_domain" "main" {
  count = var.use_managed_opensearch ? 1 : 0

  depends_on = [aws_iam_service_linked_role.opensearch]

  domain_name    = "${var.project_name}-${var.environment}"
  engine_version = "OpenSearch_2.11"

  cluster_config {
    instance_type  = var.opensearch_instance_type
    instance_count = var.opensearch_instance_count
  }

  ebs_options {
    ebs_enabled = true
    volume_type = "gp3"
    volume_size = 20
  }

  vpc_options {
    subnet_ids         = [local.private_subnet_ids[0]]
    security_group_ids = [aws_security_group.opensearch[0].id]
  }

  node_to_node_encryption {
    enabled = true
  }

  encrypt_at_rest {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  advanced_options = {
    "rest.action.multi.allow_explicit_index" = "true"
  }

  # VPC deployment: access is controlled by security group, not IP-based policy.
  # IP-based policies are incompatible with VPC endpoints.
  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action   = "es:*"
        Resource = "arn:aws:es:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:domain/${var.project_name}-${var.environment}/*"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-opensearch"
  }
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
