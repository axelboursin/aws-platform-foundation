# Applied once, manually, by an administrator of the management account
# (local state, then optionally migrated into the bucket it creates).
#
# Creates the state bucket and the two pipeline roles used by GitHub Actions:
#   platform-terraform-plan   read-only, assumable from pull requests
#   platform-terraform-apply  admin of the management account, assumable only
#                             from the protected "management" environment
terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

locals {
  platform = yamldecode(file("${path.module}/../../config/platform.yaml"))
  repo     = "${local.platform.github_owner}/${var.repository_name}"
}

provider "aws" {
  region = local.platform.home_region
  default_tags {
    tags = { ManagedBy = "terraform", Stack = "00-bootstrap", Repository = local.repo }
  }
}

data "aws_caller_identity" "current" {}

resource "aws_kms_key" "state" {
  description         = "Terraform state encryption"
  enable_key_rotation = true
}

resource "aws_s3_bucket" "state" {
  bucket = "${local.platform.name}-platform-tfstate-${data.aws_caller_identity.current.account_id}"
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "state" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/*"]
  }
  statement {
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.state.arn]
  }
}

module "plan_role" {
  source = "../../modules/github_oidc_role"

  name                = "platform-terraform-plan"
  oidc_provider_arn   = aws_iam_openid_connect_provider.github.arn
  repository          = local.repo
  subjects            = ["pull_request"]
  managed_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
  inline_policy_json  = data.aws_iam_policy_document.plan.json
}

data "aws_iam_policy_document" "plan" {
  source_policy_documents = [data.aws_iam_policy_document.state.json]

  # Read-only role created by the account baseline in every member account.
  statement {
    actions   = ["sts:AssumeRole"]
    resources = ["arn:aws:iam::*:role/platform-terraform-plan"]
  }

  # Identity Center group lookups are not covered by ReadOnlyAccess.
  statement {
    actions   = ["identitystore:GetGroupId", "identitystore:DescribeGroup"]
    resources = ["*"]
  }
}

module "apply_role" {
  source = "../../modules/github_oidc_role"

  name              = "platform-terraform-apply"
  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  repository        = local.repo
  subjects          = ["environment:management"]
  # Managing an AWS Organization requires broad rights in the management
  # account. Compensating controls: protected environment with required
  # reviewers, main-only deployment, no workloads in this account, CloudTrail.
  managed_policy_arns = ["arn:aws:iam::aws:policy/AdministratorAccess"]
}
