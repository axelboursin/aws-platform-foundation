variable "accounts" {
  description = "Member accounts to vend (usually yamldecode(file(\"config/accounts.yaml\")).accounts)."
  type = list(object({
    name               = string
    ou                 = string
    environment        = string
    owner              = string
    owner_email        = optional(string)
    monthly_budget_usd = optional(number, 0)
  }))

  validation {
    condition     = length(var.accounts) == length(distinct([for a in var.accounts : a.name]))
    error_message = "Account names must be unique."
  }

  validation {
    condition     = alltrue([for a in var.accounts : can(regex("^[a-z][a-z0-9-]{2,40}$", a.name))])
    error_message = "Account names must be lowercase kebab-case (3-41 characters)."
  }

  validation {
    condition     = alltrue([for a in var.accounts : contains(["shared", "dev", "staging", "prod", "sandbox"], a.environment)])
    error_message = "environment must be one of shared, dev, staging, prod, sandbox."
  }
}

variable "ou_ids" {
  description = "OU path (e.g. Workloads/Prod) => OU ID."
  type        = map(string)
}

variable "email_local_part" {
  description = "Local part of the shared mailbox, e.g. aws for aws@example.com."
  type        = string
}

variable "email_domain" {
  type = string
}

variable "default_budget_email" {
  description = "Budget alert recipient when an account has no owner_email."
  type        = string
}

variable "org_access_role_name" {
  type    = string
  default = "OrganizationAccountAccessRole"
}

variable "tags" {
  type    = map(string)
  default = {}
}
