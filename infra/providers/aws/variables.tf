
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

variable "tenant" {
  type        = string
  description = "Stack owner: \"shared\" for the shared stack, otherwise the dedicated tenant name."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.tenant))
    error_message = "Tenant must be 2-31 lowercase letters, numbers, or hyphens."
  }
}

variable "residency" {
  type        = string
  description = "Data residency class. \"eu\" enforces the approved-EU-region guard on plan."

  validation {
    condition     = contains(["eu", "us", "any"], var.residency)
    error_message = "Residency must be one of eu, us, any."
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

variable "kubernetes_version" {
  type    = string
  default = "1.31"
}

variable "app_node_instance_types" {
  type    = list(string)
  default = ["c6i.xlarge"]
}

variable "app_nodes_min" {
  type    = number
  default = 3
}

variable "app_nodes_max" {
  type    = number
  default = 20
}

variable "db_instance_class" {
  type    = string
  default = "db.r6g.xlarge"
}

variable "db_allocated_storage_gb" {
  type    = number
  default = 200
}

variable "db_backup_retention_days" {
  type    = number
  default = 14

  validation {
    condition     = var.db_backup_retention_days >= 7
    error_message = "Keep at least 7 days of PITR backups."
  }
}

variable "redis_node_type" {
  type    = string
  default = "cache.r7g.large"
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

# EU residency guard: an EU stack cannot even plan outside approved EU regions.
# Backups, snapshots and logs of every resource in this root stay in var.aws_region;
# no cross-region replication is configured for EU stacks.
resource "terraform_data" "eu_region_guard" {
  count = var.residency == "eu" ? 1 : 0
  input = var.aws_region

  lifecycle {
    precondition {
      condition     = contains(local.approved_eu_regions, var.aws_region)
      error_message = "Residency is eu but the region is not in the approved EU region list."
    }
  }
}
