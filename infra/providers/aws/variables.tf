variable "aws_region" { type = string }
variable "environment" { type = string }
variable "vpc_cidr" { type = string }
variable "private_subnet_cidrs" { type = list(string) }
variable "public_subnet_cidrs" { type = list(string) }
variable "eks_cluster_name" { type = string }
variable "enable_eu_residency_guard" {
  type    = bool
  default = false
}
locals {
  approved_eu_regions = ["eu-central-1", "eu-west-1", "eu-west-2", "eu-west-3", "eu-north-1", "eu-south-1"]
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
