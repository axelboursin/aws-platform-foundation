terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  backend "s3" {
    use_lockfile = true
    encrypt      = true
  }
}

# Management account: organization trail.
provider "aws" {
  region = local.platform.home_region
  default_tags {
    tags = { ManagedBy = "terraform", Stack = "30-security-services" }
  }
}

# Security tooling account: delegated administrator of GuardDuty, Security Hub
# and IAM Access Analyzer for the whole organization.
provider "aws" {
  alias  = "security"
  region = local.platform.home_region

  assume_role {
    role_arn     = "arn:aws:iam::${local.org.account_ids["security-tooling"]}:role/${var.member_role_name}"
    session_name = "platform-terraform"
  }

  default_tags {
    tags = { ManagedBy = "terraform", Stack = "30-security-services" }
  }
}
