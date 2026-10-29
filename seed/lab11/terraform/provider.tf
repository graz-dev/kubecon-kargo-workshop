terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  backend "s3" {
    bucket       = "@@AWS_STATE_BUCKET@@"
    region       = "@@AWS_REGION@@"
    key          = "${var.participant}/@@TF_STAGE@@/terraform.tfstate"
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region

  # Everything that can be tagged gets these tags
  default_tags {
    tags = {
      owner       = var.owner_email
      cost_center = var.cost_center
      purpose     = var.purpose
      participant = var.participant
    }
  }
}
