terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  # One state per account: -backend-config="key=platform/50-account-baseline/<account>.tfstate"
  backend "s3" {
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = local.platform.home_region

  assume_role {
    role_arn     = "arn:aws:iam::${local.account_id}:role/${var.member_role_name}"
    session_name = "platform-terraform"
  }

  default_tags {
    tags = {
      ManagedBy   = "terraform"
      Stack       = "50-account-baseline"
      Environment = local.account.environment
      Owner       = local.account.owner
    }
  }
}
