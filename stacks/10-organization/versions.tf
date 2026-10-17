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
  default_tags {
    tags = { ManagedBy = "terraform", Stack = "10-organization" }
  }
}
