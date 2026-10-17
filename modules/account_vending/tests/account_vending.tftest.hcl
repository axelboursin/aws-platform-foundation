mock_provider "aws" {}

variables {
  email_local_part     = "aws"
  email_domain         = "example.com"
  default_budget_email = "finops@example.com"
  ou_ids = {
    "Security"          = "ou-ab12-11111111"
    "Workloads/NonProd" = "ou-ab12-22222222"
    "Workloads/Prod"    = "ou-ab12-33333333"
  }
  accounts = [
    { name = "log-archive", ou = "Security", environment = "shared", owner = "platform" },
    { name = "data-dev", ou = "Workloads/NonProd", environment = "dev", owner = "data", monthly_budget_usd = 150, owner_email = "data@example.com" },
    { name = "data-prod", ou = "Workloads/Prod", environment = "prod", owner = "data", monthly_budget_usd = 800 },
  ]
}

run "accounts_land_in_their_ou_with_plus_addressed_email" {
  command = plan

  assert {
    condition     = aws_organizations_account.this["data-prod"].parent_id == "ou-ab12-33333333"
    error_message = "data-prod must be created in the Prod OU."
  }

  assert {
    condition     = aws_organizations_account.this["log-archive"].email == "aws+log-archive@example.com"
    error_message = "Email must use plus-addressing on the shared mailbox."
  }

  assert {
    condition     = aws_organizations_account.this["data-dev"].iam_user_access_to_billing == "DENY"
    error_message = "Billing access for IAM users must be denied."
  }
}

run "budgets_only_for_accounts_with_a_limit" {
  command = plan

  assert {
    condition     = length(aws_budgets_budget.account) == 2
    error_message = "Only accounts with monthly_budget_usd > 0 get a budget."
  }

  assert {
    condition     = contains(flatten(aws_budgets_budget.account["data-dev"].notification[*].subscriber_email_addresses), "data@example.com")
    error_message = "Budget alerts go to the account owner."
  }

  assert {
    condition     = contains(flatten(aws_budgets_budget.account["data-prod"].notification[*].subscriber_email_addresses), "finops@example.com")
    error_message = "Without owner_email, alerts go to the default recipient."
  }
}

run "unknown_ou_is_rejected" {
  command = plan

  variables {
    accounts = [{ name = "rogue", ou = "Shadow-IT", environment = "dev", owner = "x" }]
  }

  expect_failures = [aws_organizations_account.this]
}

run "duplicate_names_are_rejected" {
  command = plan

  variables {
    accounts = [
      { name = "data-dev", ou = "Security", environment = "dev", owner = "x" },
      { name = "data-dev", ou = "Security", environment = "dev", owner = "y" },
    ]
  }

  expect_failures = [var.accounts]
}
