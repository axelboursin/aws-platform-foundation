variable "name_prefix" {
  description = "Prefix for policy names."
  type        = string
  default     = "guardrail"
}

variable "allowed_regions" {
  description = "Regions where regional services may be used."
  type        = list(string)

  validation {
    condition     = length(var.allowed_regions) > 0 && alltrue([for r in var.allowed_regions : can(regex("^[a-z]{2}(-gov)?-[a-z]+-\\d$", r))])
    error_message = "Provide at least one valid region name, e.g. eu-west-3."
  }
}

variable "org_access_role_name" {
  description = "Role created in every member account for administrative access from the management account."
  type        = string
  default     = "OrganizationAccountAccessRole"
}

variable "exempt_principal_arn_patterns" {
  description = "Principals (ARN patterns) allowed to bypass the guardrails, e.g. the Terraform pipeline roles."
  type        = list(string)

  validation {
    condition     = alltrue([for p in var.exempt_principal_arn_patterns : startswith(p, "arn:aws:iam::") && p != "arn:aws:iam::*:*"])
    error_message = "Exemptions must be IAM principal ARN patterns and cannot exempt everyone."
  }
}

variable "attachments" {
  description = "Static label (root, OU name) => target ID and the policy names to attach to it."
  type = map(object({
    target_id = string
    policies  = list(string)
  }))

  validation {
    condition = alltrue([
      for a in values(var.attachments) : alltrue([
        for n in a.policies : contains([
          "deny-leave-organization", "deny-root-user", "protect-security-baseline", "deny-iam-users",
          "region-lock", "workload-guardrails", "deny-all",
        ], n)
      ])
    ])
    error_message = "Unknown policy name in attachments."
  }
}
