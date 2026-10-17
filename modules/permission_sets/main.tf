# IAM Identity Center: permission sets and group -> account assignments.
# Groups come from the external IdP (SCIM); this module only references them.

data "aws_ssoadmin_instances" "this" {}

locals {
  instance_arn      = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  identity_store_id = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]

  groups = toset([for a in var.assignments : a.group])

  assignment_map = merge([
    for a in var.assignments : {
      for account_id in a.account_ids :
      "${a.group}|${a.permission_set}|${account_id}" => merge(a, { account_id = account_id })
    }
  ]...)

  managed_attachments = merge([
    for name, ps in var.permission_sets : {
      for arn in ps.managed_policy_arns : "${name}|${arn}" => { permission_set = name, policy_arn = arn }
    }
  ]...)
}

data "aws_identitystore_group" "this" {
  for_each = local.groups

  identity_store_id = local.identity_store_id

  alternate_identifier {
    unique_attribute {
      attribute_path  = "DisplayName"
      attribute_value = each.key
    }
  }
}

resource "aws_ssoadmin_permission_set" "this" {
  for_each = var.permission_sets

  name             = each.key
  description      = each.value.description
  instance_arn     = local.instance_arn
  session_duration = each.value.session_duration
  tags             = { Privileged = tostring(each.value.privileged) }
}

resource "aws_ssoadmin_managed_policy_attachment" "this" {
  for_each = local.managed_attachments

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.permission_set].arn
  managed_policy_arn = each.value.policy_arn
}

resource "aws_ssoadmin_permission_set_inline_policy" "this" {
  for_each = { for name, ps in var.permission_sets : name => ps if ps.inline_policy_json != null }

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.key].arn
  inline_policy      = each.value.inline_policy_json
}

resource "aws_ssoadmin_account_assignment" "this" {
  for_each = local.assignment_map

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.permission_set].arn
  principal_type     = "GROUP"
  principal_id       = data.aws_identitystore_group.this[each.value.group].group_id
  target_type        = "AWS_ACCOUNT"
  target_id          = each.value.account_id

  lifecycle {
    precondition {
      condition     = contains(keys(var.permission_sets), each.value.permission_set)
      error_message = "Assignment ${each.key} uses an undefined permission set."
    }
    precondition {
      condition     = !(try(var.permission_sets[each.value.permission_set].privileged, false) && contains(var.restricted_account_ids, each.value.account_id))
      error_message = "Privileged permission set ${each.value.permission_set} cannot be assigned to restricted account ${each.value.account_id}; use the break-glass procedure."
    }
  }
}
