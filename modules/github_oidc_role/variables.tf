variable "name" {
  type = string
}

variable "oidc_provider_arn" {
  description = "ARN of the token.actions.githubusercontent.com provider in this account."
  type        = string
}

variable "repository" {
  description = "owner/name of the GitHub repository."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.repository))
    error_message = "repository must be owner/name, without wildcards."
  }
}

variable "subjects" {
  description = "Allowed token subjects after repo:<owner>/<name>:, e.g. environment:prod, ref:refs/heads/main, pull_request."
  type        = list(string)

  validation {
    condition = length(var.subjects) > 0 && alltrue([
      for s in var.subjects : !strcontains(s, "*") && can(regex("^(environment:[A-Za-z0-9_.-]+|ref:refs/(heads|tags)/[A-Za-z0-9_./-]+|pull_request)$", s))
    ])
    error_message = "Subjects must be explicit environment:<name>, ref:refs/heads|tags/<name> or pull_request, without wildcards."
  }
}

variable "managed_policy_arns" {
  type    = list(string)
  default = []
}

variable "inline_policy_json" {
  type    = string
  default = null
}

variable "permissions_boundary_arn" {
  type    = string
  default = null
}

variable "max_session_duration" {
  type    = number
  default = 3600
}

variable "tags" {
  type    = map(string)
  default = {}
}
