data "aws_availability_zones" "available" { state = "available" }
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
}
resource "aws_internet_gateway" "this" { vpc_id = aws_vpc.this.id }
resource "aws_subnet" "private" {
  for_each                = { for idx, cidr in var.private_subnet_cidrs : idx => cidr }
  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value
  availability_zone       = data.aws_availability_zones.available.names[tonumber(each.key) % length(data.aws_availability_zones.available.names)]
  map_public_ip_on_launch = false
  tags                    = { Tier = "private", Name = "${var.environment}-private-${each.key}" }
}
resource "aws_subnet" "public" {
  for_each                = { for idx, cidr in var.public_subnet_cidrs : idx => cidr }
  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value
  availability_zone       = data.aws_availability_zones.available.names[tonumber(each.key) % length(data.aws_availability_zones.available.names)]
  map_public_ip_on_launch = true
  tags                    = { Tier = "public", Name = "${var.environment}-public-${each.key}" }
}
# This starter intentionally omits route tables, NAT, VPC endpoints and flow logs.
