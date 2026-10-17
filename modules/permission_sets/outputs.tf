output "permission_set_arns" {
  value = { for name, ps in aws_ssoadmin_permission_set.this : name => ps.arn }
}

output "assignment_count" {
  value = length(aws_ssoadmin_account_assignment.this)
}
