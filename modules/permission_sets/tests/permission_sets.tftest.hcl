mock_provider "aws" {
  mock_data "aws_ssoadmin_instances" {
    defaults = {
      arns               = ["arn:aws:sso:::instance/ssoins-1234567890abcdef"]
      identity_store_ids = ["d-1234567890"]
    }
  }
  mock_data "aws_identitystore_group" {
    defaults = {
      group_id = "906752a1c6-11111111-2222-3333-4444-555555555555"
    }
  }
}

variables {
  permission_sets = {
    PlatformAdmin = {
      description         = "Full admin, sandbox and non-prod only"
      session_duration    = "PT1H"
      managed_policy_arns = ["arn:aws:iam::aws:policy/AdministratorAccess"]
      privileged          = true
    }
    ReadOnly = {
      description         = "Read-only access"
      managed_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
    }
  }
  assignments = [
    { group = "platform-engineers", permission_set = "PlatformAdmin", account_ids = ["111111111111", "222222222222"] },
    { group = "platform-engineers", permission_set = "ReadOnly", account_ids = ["111111111111", "222222222222", "333333333333"] },
    { group = "data-engineers", permission_set = "ReadOnly", account_ids = ["333333333333"] },
  ]
  restricted_account_ids = ["333333333333"]
}

run "assignments_expand_per_account" {
  command = plan

  assert {
    condition     = output.assignment_count == 6
    error_message = "Expected 2 + 3 + 1 assignments."
  }

  assert {
    condition     = length(aws_ssoadmin_managed_policy_attachment.this) == 2
    error_message = "One managed policy per permission set."
  }
}

run "privileged_set_cannot_reach_restricted_account" {
  command = plan

  variables {
    assignments = [{ group = "platform-engineers", permission_set = "PlatformAdmin", account_ids = ["333333333333"] }]
  }

  expect_failures = [aws_ssoadmin_account_assignment.this]
}

run "privileged_sessions_are_short" {
  command = plan

  variables {
    permission_sets = {
      PlatformAdmin = {
        description      = "too long"
        session_duration = "PT8H"
        privileged       = true
      }
    }
    assignments = []
  }

  expect_failures = [var.permission_sets]
}
