variable "trail_name" {
  description = "Name of the organization trail created by 30-security-services."
  type        = string
  default     = "org-trail"
}

variable "retention_days" {
  description = "How long CloudTrail logs are kept."
  type        = number
  default     = 2557 # 7 years
}
