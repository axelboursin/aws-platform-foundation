output "role_arn" {
  value = aws_iam_role.this.arn
}

output "trust_policy" {
  value = jsonencode(local.trust_policy)
}
