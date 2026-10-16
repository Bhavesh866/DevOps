
variable "aws_region" {
  type = string
}

variable "environment" {
  type = string

  validation {
    condition     = can(regex("^[a-z0-9-]{2,20}$", var.environment))
    error_message = "Environment must be 2-20 lowercase letters, numbers, or hyphens."
  }
}

variable "vpc_cidr" {
  type = string

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "private_subnet_cidrs" {
  type = list(string)

  validation {
    condition     = length(var.private_subnet_cidrs) >= 2
    error_message = "At least two private subnets are required for multi-AZ deployment."
  }

  validation {
    condition = (
      length(distinct(var.private_subnet_cidrs)) == length(var.private_subnet_cidrs) &&
      alltrue([for cidr in var.private_subnet_cidrs : can(cidrnetmask(cidr))])
    )
    error_message = "Private subnet CIDRs must be valid and unique."
  }
}

variable "public_subnet_cidrs" {
  type = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) >= 2
    error_message = "At least two public subnets are required for multi-AZ deployment."
  }

  validation {
    condition = (
      length(distinct(var.public_subnet_cidrs)) == length(var.public_subnet_cidrs) &&
      alltrue([for cidr in var.public_subnet_cidrs : can(cidrnetmask(cidr))])
    )
    error_message = "Public subnet CIDRs must be valid and unique."
  }
}

variable "eks_cluster_name" {
  type = string
}

variable "enable_eu_residency_guard" {
  type    = bool
  default = false
}

locals {
  approved_eu_regions = [
    "eu-central-1",
    "eu-west-1",
    "eu-west-2",
    "eu-west-3",
    "eu-north-1",
    "eu-south-1",
  ]
}

resource "terraform_data" "eu_region_guard" {
  count = var.enable_eu_residency_guard ? 1 : 0
  input = var.aws_region

  lifecycle {
    precondition {
      condition     = contains(local.approved_eu_regions, var.aws_region)
      error_message = "Region is not in the configured approved EU region list."
    }
  }
}