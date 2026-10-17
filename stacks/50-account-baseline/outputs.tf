output "account_id" {
  value = local.account_id
}

output "github_role_arns" {
  value = { for name, role in module.github_roles : name => role.role_arn }
}
