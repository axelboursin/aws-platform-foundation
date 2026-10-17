variable "security_alert_email" {
  description = "Recipient of high-severity GuardDuty findings."
  type        = string
  default     = "security@example.com"
}
