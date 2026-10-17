output "organization_id" {
  value = aws_organizations_organization.this.id
}

output "management_account_id" {
  value = aws_organizations_organization.this.master_account_id
}

output "root_id" {
  value = local.root_id
}

output "ou_ids" {
  value = local.ou_ids
}

output "account_ids" {
  value = module.accounts.account_ids
}

output "accounts_by_environment" {
  value = module.accounts.accounts_by_environment
}
