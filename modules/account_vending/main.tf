# Account vending: member accounts are declared in config/accounts.yaml and
# created in their OU. Each gets an email derived from a single mailbox with
# plus-addressing, and a monthly budget alert.

locals {
  accounts = { for a in var.accounts : a.name => a }
}

resource "aws_organizations_account" "this" {
  for_each = local.accounts

  name                       = each.key
  email                      = "${var.email_local_part}+${each.key}@${var.email_domain}"
  parent_id                  = lookup(var.ou_ids, each.value.ou, null)
  role_name                  = var.org_access_role_name
  iam_user_access_to_billing = "DENY"
  close_on_deletion          = false

  tags = merge(var.tags, {
    OU          = each.value.ou
    Environment = each.value.environment
    Owner       = each.value.owner
  })

  lifecycle {
    precondition {
      condition     = contains(keys(var.ou_ids), each.value.ou)
      error_message = "Account ${each.key} references unknown OU \"${each.value.ou}\"."
    }
    # Changing these after creation is not supported by the Organizations API.
    ignore_changes = [role_name, iam_user_access_to_billing, email]
    # Closing an account is a 90-day, mostly irreversible operation.
    prevent_destroy = true
  }
}

resource "aws_budgets_budget" "account" {
  for_each = { for name, a in local.accounts : name => a if a.monthly_budget_usd > 0 }

  name         = "account-${each.key}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(each.value.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "LinkedAccount"
    values = [aws_organizations_account.this[each.key].id]
  }

  dynamic "notification" {
    for_each = [{ type = "ACTUAL", threshold = 80 }, { type = "FORECASTED", threshold = 100 }]
    content {
      comparison_operator        = "GREATER_THAN"
      notification_type          = notification.value.type
      threshold                  = notification.value.threshold
      threshold_type             = "PERCENTAGE"
      subscriber_email_addresses = [coalesce(each.value.owner_email, var.default_budget_email)]
    }
  }
}
