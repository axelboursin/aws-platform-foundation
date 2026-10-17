# Management account: the organization itself, its OU tree, guardrails
# (SCPs, tag policy), member accounts, and delegated administrators.

locals {
  platform = yamldecode(file("${path.module}/../../config/platform.yaml"))
  accounts = yamldecode(file("${path.module}/../../config/accounts.yaml")).accounts

  pipeline_role_patterns = [
    "arn:aws:iam::*:role/OrganizationAccountAccessRole",
    "arn:aws:iam::*:role/platform-terraform-*",
  ]
}

resource "aws_organizations_organization" "this" {
  feature_set = "ALL"

  enabled_policy_types = ["SERVICE_CONTROL_POLICY", "TAG_POLICY"]

  aws_service_access_principals = [
    "access-analyzer.amazonaws.com",
    "account.amazonaws.com",
    "cloudtrail.amazonaws.com",
    "guardduty.amazonaws.com",
    "malware-protection.guardduty.amazonaws.com",
    "securityhub.amazonaws.com",
    "sso.amazonaws.com",
  ]

  lifecycle {
    prevent_destroy = true
  }
}

locals {
  root_id = aws_organizations_organization.this.roots[0].id
}

# OU tree ----------------------------------------------------------------------

resource "aws_organizations_organizational_unit" "top" {
  for_each = toset(["Security", "Infrastructure", "Workloads", "Sandbox", "Suspended"])

  name      = each.key
  parent_id = local.root_id
}

resource "aws_organizations_organizational_unit" "workloads" {
  for_each = toset(["Prod", "NonProd"])

  name      = each.key
  parent_id = aws_organizations_organizational_unit.top["Workloads"].id
}

locals {
  ou_ids = merge(
    { for name, ou in aws_organizations_organizational_unit.top : name => ou.id },
    { for name, ou in aws_organizations_organizational_unit.workloads : "Workloads/${name}" => ou.id },
  )
}

# Guardrails -------------------------------------------------------------------

module "scp" {
  source = "../../modules/scp"

  allowed_regions               = local.platform.allowed_regions
  exempt_principal_arn_patterns = local.pipeline_role_patterns

  # SCPs are inherited: what is attached to Workloads applies to Prod and NonProd.
  attachments = {
    root           = { target_id = local.root_id, policies = ["deny-leave-organization", "deny-root-user", "protect-security-baseline", "deny-iam-users"] }
    infrastructure = { target_id = local.ou_ids["Infrastructure"], policies = ["region-lock"] }
    workloads      = { target_id = local.ou_ids["Workloads"], policies = ["region-lock", "workload-guardrails"] }
    sandbox        = { target_id = local.ou_ids["Sandbox"], policies = ["region-lock", "workload-guardrails"] }
    suspended      = { target_id = local.ou_ids["Suspended"], policies = ["deny-all"] }
  }
}

resource "aws_organizations_policy" "tagging" {
  name        = "tagging-standard"
  description = "Normalize the casing and allowed values of cost allocation tags"
  type        = "TAG_POLICY"
  content = jsonencode({
    tags = {
      environment = {
        tag_key   = { "@@assign" = "Environment" }
        tag_value = { "@@assign" = ["shared", "dev", "staging", "prod", "sandbox"] }
      }
      owner = {
        tag_key = { "@@assign" = "Owner" }
      }
    }
  })
}

resource "aws_organizations_policy_attachment" "tagging" {
  policy_id = aws_organizations_policy.tagging.id
  target_id = local.root_id
}

# Member accounts ----------------------------------------------------------------

module "accounts" {
  source = "../../modules/account_vending"

  accounts             = local.accounts
  ou_ids               = local.ou_ids
  email_local_part     = local.platform.account_email.local_part
  email_domain         = local.platform.account_email.domain
  default_budget_email = local.platform.budget_alert_email
}

# Delegated administrators: security services are run from security-tooling,
# never from the management account.

locals {
  security_account_id = module.accounts.account_ids["security-tooling"]
}

resource "aws_guardduty_organization_admin_account" "this" {
  admin_account_id = local.security_account_id
  depends_on       = [aws_organizations_organization.this]
}

resource "aws_securityhub_organization_admin_account" "this" {
  admin_account_id = local.security_account_id
  depends_on       = [aws_organizations_organization.this]
}

resource "aws_organizations_delegated_administrator" "access_analyzer" {
  account_id        = local.security_account_id
  service_principal = "access-analyzer.amazonaws.com"
}
