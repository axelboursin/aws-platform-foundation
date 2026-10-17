mock_provider "aws" {}

variables {
  allowed_regions               = ["eu-west-3", "eu-west-1"]
  exempt_principal_arn_patterns = ["arn:aws:iam::*:role/OrganizationAccountAccessRole", "arn:aws:iam::*:role/platform-terraform-*"]
  attachments = {
    root      = { target_id = "r-ab12", policies = ["deny-leave-organization", "deny-root-user", "protect-security-baseline", "deny-iam-users"] }
    workloads = { target_id = "ou-ab12-11111111", policies = ["region-lock", "workload-guardrails"] }
    suspended = { target_id = "ou-ab12-22222222", policies = ["deny-all"] }
  }
}

run "every_policy_fits_the_scp_size_limit" {
  command = plan

  assert {
    condition     = alltrue([for doc in values(output.policy_documents) : length(doc) <= 5120])
    error_message = "An SCP exceeds 5,120 characters."
  }
}

run "only_attached_policies_are_created" {
  command = plan

  assert {
    condition     = length(aws_organizations_policy.this) == 7
    error_message = "Expected the 7 attached policies."
  }

  assert {
    condition     = length(aws_organizations_policy_attachment.this) == 7
    error_message = "Expected one attachment per (policy, target) pair."
  }
}

run "region_lock_targets_requested_region_and_exempts_pipeline" {
  command = plan

  assert {
    condition     = jsondecode(output.policy_documents["region-lock"]).Statement[0].Condition.StringNotEquals["aws:RequestedRegion"] == ["eu-west-3", "eu-west-1"]
    error_message = "Region lock must use the allowed regions."
  }

  assert {
    condition     = contains(jsondecode(output.policy_documents["region-lock"]).Statement[0].NotAction, "iam:*")
    error_message = "Global services such as IAM must be excluded from the region lock."
  }

  assert {
    condition     = contains(jsondecode(output.policy_documents["region-lock"]).Statement[0].Condition.ArnNotLike["aws:PrincipalArn"], "arn:aws:iam::*:role/platform-terraform-*")
    error_message = "Pipeline roles must be exempted."
  }
}

run "root_user_is_denied" {
  command = plan

  assert {
    condition     = jsondecode(output.policy_documents["deny-root-user"]).Statement[0].Condition.ArnLike["aws:PrincipalArn"] == ["arn:aws:iam::*:root"]
    error_message = "deny-root-user must match the root principal."
  }
}

run "rejects_unknown_policy" {
  command = plan

  variables {
    attachments = { root = { target_id = "r-ab12", policies = ["allow-everything"] } }
  }

  expect_failures = [var.attachments]
}

run "rejects_exempting_everyone" {
  command = plan

  variables {
    exempt_principal_arn_patterns = ["arn:aws:iam::*:*"]
  }

  expect_failures = [var.exempt_principal_arn_patterns]
}
