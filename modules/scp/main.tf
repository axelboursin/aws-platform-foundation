# Service control policies, written with jsonencode so their content can be
# unit-tested (terraform test) and their size checked against the 5,120-character limit.

locals {
  # Principals allowed through the guardrails: the org access role used for
  # break-glass and the Terraform pipeline roles.
  exempt_principals = var.exempt_principal_arn_patterns

  # Global services whose API calls resolve to us-east-1; excluded from region lock.
  global_actions = [
    "a4b:*", "account:*", "aws-portal:*", "budgets:*", "ce:*", "chime:*", "cloudfront:*",
    "config:*", "cur:*", "directconnect:*", "ec2:DescribeRegions", "ec2:DescribeTransitGateways",
    "ec2:DescribeVpnGateways", "fms:*", "globalaccelerator:*", "health:*", "iam:*",
    "importexport:*", "kms:*", "mobileanalytics:*", "networkmanager:*", "organizations:*",
    "pricing:*", "route53:*", "route53domains:*", "route53-recovery-cluster:*",
    "route53-recovery-control-config:*", "route53-recovery-readiness:*", "s3:GetAccountPublic*",
    "s3:ListAllMyBuckets", "s3:ListMultiRegionAccessPoints", "s3:PutAccountPublic*", "shield:*",
    "sso:*", "sts:*", "support:*", "trustedadvisor:*", "waf-regional:*", "waf:*", "wafv2:*",
  ]

  exempt_condition = {
    ArnNotLike = { "aws:PrincipalArn" = local.exempt_principals }
  }

  documents = {
    deny-leave-organization = {
      description = "Accounts cannot leave the organization"
      statements = [{
        Sid      = "DenyLeaveOrganization"
        Effect   = "Deny"
        Action   = ["organizations:LeaveOrganization"]
        Resource = "*"
      }]
    }

    deny-root-user = {
      description = "The root user of member accounts cannot be used"
      statements = [{
        Sid       = "DenyRootUser"
        Effect    = "Deny"
        Action    = "*"
        Resource  = "*"
        Condition = { ArnLike = { "aws:PrincipalArn" = ["arn:aws:iam::*:root"] } }
      }]
    }

    protect-security-baseline = {
      description = "Logging, threat detection and the org access role cannot be tampered with"
      statements = [
        {
          Sid    = "ProtectAuditServices"
          Effect = "Deny"
          Action = [
            "cloudtrail:DeleteTrail", "cloudtrail:PutEventSelectors", "cloudtrail:StopLogging",
            "cloudtrail:UpdateTrail",
            "config:DeleteConfigurationRecorder", "config:DeleteDeliveryChannel",
            "config:StopConfigurationRecorder",
            "guardduty:DeleteDetector", "guardduty:DisassociateFromAdministratorAccount",
            "guardduty:DisassociateFromMasterAccount", "guardduty:UpdateDetector",
            "securityhub:DisableSecurityHub", "securityhub:DisassociateFromAdministratorAccount",
            "access-analyzer:DeleteAnalyzer",
          ]
          Resource  = "*"
          Condition = local.exempt_condition
        },
        {
          Sid       = "ProtectOrgAccessRole"
          Effect    = "Deny"
          Action    = ["iam:AttachRolePolicy", "iam:DeleteRole", "iam:DeleteRolePolicy", "iam:DetachRolePolicy", "iam:PutRolePolicy", "iam:UpdateAssumeRolePolicy", "iam:UpdateRole"]
          Resource  = ["arn:aws:iam::*:role/${var.org_access_role_name}"]
          Condition = local.exempt_condition
        },
      ]
    }

    deny-iam-users = {
      description = "Humans use Identity Center, workloads use roles: no IAM users or access keys"
      statements = [{
        Sid       = "DenyLongLivedCredentials"
        Effect    = "Deny"
        Action    = ["iam:CreateUser", "iam:CreateAccessKey", "iam:CreateLoginProfile"]
        Resource  = "*"
        Condition = local.exempt_condition
      }]
    }

    region-lock = {
      description = "Regional services can only be used in approved regions"
      statements = [{
        Sid       = "DenyOutsideApprovedRegions"
        Effect    = "Deny"
        NotAction = local.global_actions
        Resource  = "*"
        Condition = merge(local.exempt_condition, {
          StringNotEquals = { "aws:RequestedRegion" = var.allowed_regions }
        })
      }]
    }

    workload-guardrails = {
      description = "Secure defaults for workload accounts"
      statements = [
        {
          Sid       = "RequireImdsV2"
          Effect    = "Deny"
          Action    = "ec2:RunInstances"
          Resource  = "arn:aws:ec2:*:*:instance/*"
          Condition = { StringNotEquals = { "ec2:MetadataHttpTokens" = "required" } }
        },
        {
          Sid       = "DenyUnencryptedVolumes"
          Effect    = "Deny"
          Action    = "ec2:CreateVolume"
          Resource  = "*"
          Condition = { Bool = { "ec2:Encrypted" = "false" } }
        },
        {
          Sid       = "ProtectS3AccountPublicAccessBlock"
          Effect    = "Deny"
          Action    = ["s3:PutAccountPublicAccessBlock"]
          Resource  = "*"
          Condition = local.exempt_condition
        },
      ]
    }

    deny-all = {
      description = "Quarantine: suspended accounts can do nothing"
      statements = [{
        Sid      = "DenyAll"
        Effect   = "Deny"
        Action   = "*"
        Resource = "*"
      }]
    }
  }

  policies = {
    for name, doc in local.documents : name => {
      description = doc.description
      content     = jsonencode({ Version = "2012-10-17", Statement = doc.statements })
    }
  }

  # Keys are static labels (root, OU names) so for_each works on the first
  # apply, when the target IDs are still unknown.
  used_policies = toset(flatten([for a in values(var.attachments) : a.policies]))

  attachment_pairs = merge([
    for label, a in var.attachments : {
      for name in a.policies : "${name}|${label}" => { policy = name, target_id = a.target_id }
    }
  ]...)
}

resource "aws_organizations_policy" "this" {
  for_each = local.used_policies

  name        = "${var.name_prefix}-${each.key}"
  description = local.policies[each.key].description
  type        = "SERVICE_CONTROL_POLICY"
  content     = local.policies[each.key].content
}

resource "aws_organizations_policy_attachment" "this" {
  for_each = local.attachment_pairs

  policy_id = aws_organizations_policy.this[each.value.policy].id
  target_id = each.value.target_id
}
