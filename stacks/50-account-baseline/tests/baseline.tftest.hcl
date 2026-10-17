mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_resource "aws_iam_openid_connect_provider" {
    defaults = { arn = "arn:aws:iam::200000000004:oidc-provider/token.actions.githubusercontent.com" }
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

run "data_dev_gets_its_github_roles" {
  command = plan

  variables {
    account_name = "data-dev"
  }

  assert {
    condition     = toset(keys(module.github_roles)) == toset(["bess-iot-plan", "bess-iot-apply"])
    error_message = "data-dev must get the two roles declared in config/accounts.yaml."
  }

  assert {
    condition     = aws_iam_account_alias.this.account_alias == "acme-data-dev"
    error_message = "Account alias must be <org>-<account>."
  }

  assert {
    condition     = aws_ec2_instance_metadata_defaults.this.http_tokens == "required"
    error_message = "IMDSv2 must be the account default."
  }
}

run "accounts_without_repositories_get_no_oidc_provider" {
  command = plan

  variables {
    account_name = "data-prod"
  }

  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 0
    error_message = "No GitHub OIDC provider without declared repositories."
  }
}
