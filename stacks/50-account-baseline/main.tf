# Baseline applied to every member account (CI runs it as a matrix, one state
# per account): secure defaults, the read-only plan role, and GitHub OIDC
# roles for the repositories declared in config/accounts.yaml.

locals {
  accounts   = { for a in yamldecode(file("${path.module}/../../config/accounts.yaml")).accounts : a.name => a }
  account    = local.accounts[var.account_name]
  account_id = local.org.account_ids[var.account_name]
  github     = { for g in try(local.account.github, []) : g.role => g }
}

check "account_is_declared" {
  assert {
    condition     = contains(keys(local.accounts), var.account_name)
    error_message = "${var.account_name} is not declared in config/accounts.yaml."
  }
}

resource "aws_iam_account_alias" "this" {
  account_alias = "${local.platform.name}-${var.account_name}"
}

resource "aws_s3_account_public_access_block" "this" {
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_ebs_encryption_by_default" "this" {
  enabled = true
}

resource "aws_ec2_instance_metadata_defaults" "this" {
  http_tokens                 = "required"
  http_put_response_hop_limit = 2
}

# Read-only role used by pull-request plans (assumed from the management
# account's platform-terraform-plan role).
data "aws_iam_policy_document" "plan_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.org.management_account_id}:role/platform-terraform-plan"]
    }
  }
}

resource "aws_iam_role" "plan" {
  name                 = "platform-terraform-plan"
  assume_role_policy   = data.aws_iam_policy_document.plan_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "plan" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# GitHub Actions deployment roles ----------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  count = length(local.github) > 0 ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

module "github_roles" {
  source   = "../../modules/github_oidc_role"
  for_each = local.github

  name                = each.key
  oidc_provider_arn   = aws_iam_openid_connect_provider.github[0].arn
  repository          = each.value.repository
  subjects            = each.value.subjects
  managed_policy_arns = try(each.value.managed_policies, [])
}
