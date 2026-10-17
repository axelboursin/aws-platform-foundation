output "cloudtrail_arn" {
  value = aws_cloudtrail.org.arn
}

output "guardduty_detector_id" {
  value = aws_guardduty_detector.security.id
}

output "security_alerts_topic_arn" {
  value = aws_sns_topic.security_alerts.arn
}
