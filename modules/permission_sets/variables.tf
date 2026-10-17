variable "permission_sets" {
  type = map(object({
    description         = string
    session_duration    = optional(string, "PT4H")
    managed_policy_arns = optional(list(string), [])
    inline_policy_json  = optional(string)
    privileged          = optional(bool, false)
  }))

  validation {
    condition     = alltrue([for ps in values(var.permission_sets) : can(regex("^PT([1-9]|1[0-2])H$", ps.session_duration))])
    error_message = "session_duration must be between PT1H and PT12H."
  }

  validation {
    condition     = alltrue([for ps in values(var.permission_sets) : !ps.privileged || ps.session_duration == "PT1H"])
    error_message = "Privileged permission sets are limited to 1-hour sessions."
  }
}

variable "assignments" {
  description = "Group display name + permission set + account IDs."
  type = list(object({
    group          = string
    permission_set = string
    account_ids    = list(string)
  }))
}

variable "restricted_account_ids" {
  description = "Accounts (typically prod and security) where privileged permission sets may not be assigned."
  type        = list(string)
  default     = []
}
