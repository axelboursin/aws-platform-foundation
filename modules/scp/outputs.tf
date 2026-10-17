output "policy_ids" {
  value = { for name, policy in aws_organizations_policy.this : name => policy.id }
}

output "policy_documents" {
  description = "Rendered policy JSON, for review and tests."
  value       = { for name in local.used_policies : name => local.policies[name].content }
}
