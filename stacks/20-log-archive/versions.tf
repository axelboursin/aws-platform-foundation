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

provider "aws" {
  region = local.platform.home_region

  assume_role {
    role_arn     = "arn:aws:iam::${local.org.account_ids["log-archive"]}:role/${var.member_role_name}"
    session_name = "platform-terraform"
  }

  default_tags {
    tags = { ManagedBy = "terraform", Stack = "20-log-archive" }
  }
}
