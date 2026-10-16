variable "project_id" { type = string }

variable "tenant" {
  type = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.tenant))
    error_message = "Tenant must be 2-31 lowercase letters, numbers, or hyphens."
  }
}

variable "primary_region" {
  type    = string
  default = "us-west1"
  validation {
    condition     = startswith(var.primary_region, "us-west")
    error_message = "CR-001 requires a US-West primary region."
  }
}

variable "failover_region" {
  type    = string
  default = "us-east1"
  validation {
    condition     = startswith(var.failover_region, "us-east")
    error_message = "CR-001 requires a US-East failover region."
  }
}

variable "primary_cidr" {
  type    = string
  default = "10.80.0.0/16"
}

variable "failover_cidr" {
  type    = string
  default = "10.81.0.0/16"
}

variable "operator_cidrs" {
  type        = list(string)
  default     = []
  description = "Extra CIDRs (VPN/bastion) allowed to reach the GKE control plane."
}

variable "machine_type" {
  type    = string
  default = "c3-standard-4"
}

variable "nodes_min_per_zone" {
  type    = number
  default = 1
}

variable "nodes_max_per_zone" {
  type    = number
  default = 6
}

variable "db_tier" {
  type    = string
  default = "db-custom-4-16384"
}

variable "redis_memory_gb" {
  type    = number
  default = 5
}
