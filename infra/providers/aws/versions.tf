terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.79" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = "continuity-platform"
      ManagedBy   = "Terraform"
      Environment = var.environment
      Tenant      = var.tenant
      Residency   = var.residency
    }
  }
}
