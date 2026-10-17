output "state_bucket" {
  value = aws_s3_bucket.state.bucket
}

output "plan_role_arn" {
  value = module.plan_role.role_arn
}

output "apply_role_arn" {
  value = module.apply_role.role_arn
}
