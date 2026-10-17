output "bucket_name" {
  value = aws_s3_bucket.trail.bucket
}

output "kms_key_arn" {
  value = aws_kms_key.trail.arn
}

output "trail_name" {
  value = var.trail_name
}
