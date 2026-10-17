mock_provider "aws" {}

variables {
  name              = "data-prod-deploy"
  oidc_provider_arn = "arn:aws:iam::111111111111:oidc-provider/token.actions.githubusercontent.com"
  repository        = "axelboursin/energy-lakehouse"
  subjects          = ["environment:prod"]
}

run "trust_is_pinned_to_repo_and_environment" {
  command = plan

  assert {
    condition     = jsondecode(output.trust_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == ["repo:axelboursin/energy-lakehouse:environment:prod"]
    error_message = "Subject must be pinned to the repository and environment."
  }

  assert {
    condition     = jsondecode(output.trust_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"] == "sts.amazonaws.com"
    error_message = "Audience must be STS."
  }
}

run "wildcard_subject_is_rejected" {
  command = plan

  variables {
    subjects = ["ref:refs/heads/*"]
  }

  expect_failures = [var.subjects]
}

run "wildcard_repository_is_rejected" {
  command = plan

  variables {
    repository = "axelboursin/*"
  }

  expect_failures = [var.repository]
}

run "inline_policy_is_optional" {
  command = plan

  assert {
    condition     = length(aws_iam_role_policy.inline) == 0
    error_message = "No inline policy expected by default."
  }
}
