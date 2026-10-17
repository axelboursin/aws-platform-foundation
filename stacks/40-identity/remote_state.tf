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
