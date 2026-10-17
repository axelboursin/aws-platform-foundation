# Account IDs and organization details come from the 10-organization stack.
data "terraform_remote_state" "org" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "platform/10-organization.tfstate"
    region = local.platform.home_region
  }
}

locals {
  platform = yamldecode(file("${path.module}/../../config/platform.yaml"))
  org      = data.terraform_remote_state.org.outputs
}

variable "state_bucket" {
  description = "Bucket created by 00-bootstrap (also used as the backend of this stack)."
  type        = string
}

variable "member_role_name" {
  description = "Role assumed in member accounts: platform-terraform-plan for plans, OrganizationAccountAccessRole for applies."
  type        = string
  default     = "OrganizationAccountAccessRole"

  validation {
    condition     = contains(["OrganizationAccountAccessRole", "platform-terraform-plan"], var.member_role_name)
    error_message = "Use OrganizationAccountAccessRole (apply) or platform-terraform-plan (plan)."
  }
}
