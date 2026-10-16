aws_region           = "eu-central-1"
environment          = "dev"
tenant               = "shared"
residency            = "eu"
vpc_cidr             = "10.40.0.0/16"
private_subnet_cidrs = ["10.40.10.0/24", "10.40.20.0/24"]
public_subnet_cidrs  = ["10.40.110.0/24", "10.40.120.0/24"]
eks_cluster_name     = "continuity-dev"
