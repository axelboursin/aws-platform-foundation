# Plan the whole stack against a mocked AWS provider, with the real
# config/*.yaml files: catches typos in OU paths, unknown policies and
# invalid account definitions before anything reaches AWS.
mock_provider "aws" {
  mock_resource "aws_organizations_organization" {
    defaults = {
      roots             = [{ id = "r-ab12", arn = "arn:aws:organizations::111111111111:root/o-abcdefghij/r-ab12", name = "Root", policy_types = [] }]
      master_account_id = "111111111111"
    }
  }
  mock_resource "aws_organizations_organizational_unit" {
    defaults = { id = "ou-ab12-12345678" }
  }
  mock_resource "aws_organizations_account" {
    defaults = { id = "222222222222" }
  }
  mock_resource "aws_organizations_policy" {
    defaults = { id = "p-12345678" }
  }
}

run "real_configuration_plans" {
  command = plan

  assert {
    condition     = length(module.accounts.account_ids) == length(yamldecode(file("../../config/accounts.yaml")).accounts)
    error_message = "Every account in config/accounts.yaml must be planned."
  }

  assert {
    condition     = length(aws_organizations_organizational_unit.workloads) == 2
    error_message = "Workloads must have Prod and NonProd."
  }

  assert {
    condition     = alltrue([for doc in values(module.scp.policy_documents) : length(doc) <= 5120])
    error_message = "An SCP exceeds the size limit."
  }
}
