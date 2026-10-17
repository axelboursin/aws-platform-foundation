# Human access: Identity Center permission sets and group assignments,
# entirely driven by config/access.yaml.

locals {
  access      = yamldecode(file("${path.module}/../../config/access.yaml"))
  account_ids = local.org.account_ids

  permission_sets = {
    for name, ps in local.access.permission_sets : name => {
      description         = ps.description
      session_duration    = try(ps.session_duration, "PT4H")
      managed_policy_arns = try(ps.managed_policy_arns, [])
      privileged          = try(ps.privileged, false)
      inline_policy_json  = try(file("${path.module}/../../${ps.inline_policy_file}"), null)
    }
  }

  assignments = [
    for a in local.access.assignments : {
      group          = a.group
      permission_set = a.permission_set
      account_ids    = a.accounts == "all" ? values(local.account_ids) : [for name in a.accounts : local.account_ids[name]]
    }
  ]

  # Privileged sets can never be assigned to prod or to the security accounts.
  restricted_account_ids = concat(
    try(local.org.accounts_by_environment["prod"], []),
    [local.account_ids["log-archive"], local.account_ids["security-tooling"]],
  )
}

module "permission_sets" {
  source = "../../modules/permission_sets"

  permission_sets        = local.permission_sets
  assignments            = local.assignments
  restricted_account_ids = local.restricted_account_ids
}
