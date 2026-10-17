output "account_ids" {
  value = { for name, account in aws_organizations_account.this : name => account.id }
}

output "accounts_by_environment" {
  value = {
    for env in distinct([for a in var.accounts : a.environment]) :
    env => [for a in var.accounts : aws_organizations_account.this[a.name].id if a.environment == env]
  }
}
