data "terraform_remote_state" "log_archive" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "platform/20-log-archive.tfstate"
    region = local.platform.home_region
  }
}

locals {
  logs = data.terraform_remote_state.log_archive.outputs
}

# Organization CloudTrail ------------------------------------------------------
# One multi-region trail for every account, written to the log-archive bucket
# (object lock + KMS). Member accounts cannot stop it (protect-security-baseline SCP).

resource "aws_cloudtrail" "org" {
  name                          = local.logs.trail_name
  s3_bucket_name                = local.logs.bucket_name
  kms_key_id                    = local.logs.kms_key_arn
  is_organization_trail         = true
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true
}

# GuardDuty ----------------------------------------------------------------------

resource "aws_guardduty_detector" "security" {
  provider = aws.security
  enable   = true
}

resource "aws_guardduty_organization_configuration" "this" {
  provider                         = aws.security
  detector_id                      = aws_guardduty_detector.security.id
  auto_enable_organization_members = "ALL"
}

resource "aws_guardduty_organization_configuration_feature" "this" {
  for_each = toset(["S3_DATA_EVENTS", "EBS_MALWARE_PROTECTION", "RDS_LOGIN_EVENTS", "LAMBDA_NETWORK_LOGS"])

  provider    = aws.security
  detector_id = aws_guardduty_detector.security.id
  name        = each.key
  auto_enable = "ALL"
}

# Security Hub ---------------------------------------------------------------------

resource "aws_securityhub_account" "security" {
  provider                 = aws.security
  enable_default_standards = false
  auto_enable_controls     = true
}

resource "aws_securityhub_organization_configuration" "this" {
  provider              = aws.security
  auto_enable           = true
  auto_enable_standards = "DEFAULT" # AWS Foundational Security Best Practices
  depends_on            = [aws_securityhub_account.security]
}

resource "aws_securityhub_standards_subscription" "fsbp" {
  provider      = aws.security
  standards_arn = "arn:aws:securityhub:${local.platform.home_region}::standards/aws-foundational-security-best-practices/v/1.0.0"
  depends_on    = [aws_securityhub_account.security]
}

resource "aws_securityhub_finding_aggregator" "this" {
  provider          = aws.security
  linking_mode      = "SPECIFIED_REGIONS"
  specified_regions = [for r in local.platform.allowed_regions : r if r != local.platform.home_region]
  depends_on        = [aws_securityhub_account.security]
}

# IAM Access Analyzer: flags resources shared outside the organization ------------

resource "aws_accessanalyzer_analyzer" "org" {
  provider      = aws.security
  analyzer_name = "organization"
  type          = "ORGANIZATION"
}

# Findings notification: high-severity GuardDuty findings -> SNS -> email ----------

# EventBridge cannot publish to a topic encrypted with the AWS-managed SNS key:
# a customer-managed key with an explicit grant is required.
data "aws_caller_identity" "security" {
  provider = aws.security
}

data "aws_iam_policy_document" "alerts_key" {
  statement {
    sid       = "AccountAdministration"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.security.account_id}:root"]
    }
  }
  statement {
    sid       = "EventBridgePublish"
    actions   = ["kms:GenerateDataKey*", "kms:Decrypt"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_kms_key" "alerts" {
  provider            = aws.security
  description         = "Security alerts topic"
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.alerts_key.json
}

resource "aws_sns_topic" "security_alerts" {
  provider          = aws.security
  name              = "security-alerts"
  kms_master_key_id = aws_kms_key.alerts.arn
}

resource "aws_sns_topic_subscription" "email" {
  provider  = aws.security
  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "email"
  endpoint  = var.security_alert_email
}

resource "aws_cloudwatch_event_rule" "guardduty_high" {
  provider    = aws.security
  name        = "guardduty-high-severity"
  description = "GuardDuty findings with severity >= 7"
  event_pattern = jsonencode({
    source        = ["aws.guardduty"]
    "detail-type" = ["GuardDuty Finding"]
    detail        = { severity = [{ numeric = [">=", 7] }] }
  })
}

resource "aws_cloudwatch_event_target" "guardduty_high" {
  provider = aws.security
  rule     = aws_cloudwatch_event_rule.guardduty_high.name
  arn      = aws_sns_topic.security_alerts.arn
}

data "aws_iam_policy_document" "sns" {
  statement {
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.security_alerts.arn]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_event_rule.guardduty_high.arn]
    }
  }
}

resource "aws_sns_topic_policy" "security_alerts" {
  provider = aws.security
  arn      = aws_sns_topic.security_alerts.arn
  policy   = data.aws_iam_policy_document.sns.json
}
