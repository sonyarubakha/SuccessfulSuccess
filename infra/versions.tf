terraform {
  required_version = ">= 1.10"

  # Planned only: replace YOUR_HCP_ORG before initializing remote execution.
  cloud {
    organization = "successfulsuccess-lab7-org"
    workspaces {
      name = "successfulsuccess-lab7"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region              = var.region
  allowed_account_ids = [var.aws_account_id]
  default_tags {
    tags = {
      PROJECT_NAME = var.project_name
    }
  }
}

# The existing standalone SQS ingress rule has no tags. Keep provider defaults
# from introducing tags on that resource during adoption.
provider "aws" {
  alias               = "untagged"
  region              = var.region
  allowed_account_ids = [var.aws_account_id]
}

data "aws_partition" "current" {}

# This stack remains owned entirely by CloudFormation.
data "aws_cloudformation_stack" "backend" {
  name = var.backend_stack_name
}

locals {
  has_google = var.google_client_id != ""
  lambda_trust = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}
