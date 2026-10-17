# IAM role assumable by one GitHub repository through OIDC, restricted to
# explicit subjects (environments, branches or pull requests). No wildcards:
# a typo in a trust policy must not open the role to every repository.

locals {
  subjects = [for s in var.subjects : "repo:${var.repository}:${s}"]

  trust_policy = {
    Version = "2012-10-17"
    Statement = [{
      Sid       = "GitHubActionsOidc"
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = var.oidc_provider_arn }
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = local.subjects
        }
      }
    }]
  }
}

resource "aws_iam_role" "this" {
  name                 = var.name
  description          = "GitHub Actions: ${var.repository} (${join(", ", var.subjects)})"
  assume_role_policy   = jsonencode(local.trust_policy)
  max_session_duration = var.max_session_duration
  permissions_boundary = var.permissions_boundary_arn
  tags                 = merge(var.tags, { GitHubRepository = var.repository })
}

resource "aws_iam_role_policy_attachment" "managed" {
  for_each = toset(var.managed_policy_arns)

  role       = aws_iam_role.this.name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "inline" {
  count = var.inline_policy_json == null ? 0 : 1

  name   = "inline"
  role   = aws_iam_role.this.id
  policy = var.inline_policy_json
}
