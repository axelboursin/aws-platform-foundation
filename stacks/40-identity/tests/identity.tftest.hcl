# Plans config/access.yaml against mocked AWS and a mocked 10-organization state.
mock_provider "aws" {
  mock_data "aws_ssoadmin_instances" {
    defaults = {
      arns               = ["arn:aws:sso:::instance/ssoins-1234567890abcdef"]
      identity_store_ids = ["d-1234567890"]
    }
  }
  mock_data "aws_identitystore_group" {
    defaults = { group_id = "906752a1c6-11111111-2222-3333-4444-555555555555" }
  }
}

override_data {
  target = data.terraform_remote_state.org
  values = {
    outputs = {
      organization_id       = "o-abcdefghij"
      management_account_id = "111111111111"
      account_ids = {
        "log-archive"      = "200000000001"
        "security-tooling" = "200000000002"
        "shared-services"  = "200000000003"
        "data-dev"         = "200000000004"
        "data-prod"        = "200000000005"
        "sandbox-axel"     = "200000000006"
      }
      accounts_by_environment = {
        shared  = ["200000000001", "200000000002", "200000000003"]
        dev     = ["200000000004"]
        prod    = ["200000000005"]
        sandbox = ["200000000006"]
      }
    }
  }
}

variables {
  state_bucket = "acme-platform-tfstate-111111111111"
}

run "access_yaml_is_valid_and_safe" {
  command = plan

  # 3 PlatformAdmin + 6 ReadOnly + 1 DataEngineer + 1 ReadOnly + 6 SecurityAudit
  assert {
    condition     = module.permission_sets.assignment_count == 17
    error_message = "Unexpected number of assignments for config/access.yaml."
  }

  assert {
    condition     = contains(local.restricted_account_ids, "200000000005") && contains(local.restricted_account_ids, "200000000002")
    error_message = "Prod and security accounts must be restricted."
  }
}
