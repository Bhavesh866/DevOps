# Kubernetes: private EKS control plane, IRSA, audit logging, envelope
# encryption of Secrets (the module creates a KMS key by default).
# Node scaling: managed node groups + Cluster Autoscaler or Karpenter
# (platform layer). Warm headroom comes from app_nodes_min, because new nodes
# take minutes and the 15x target is 5 minutes end to end.
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name    = var.eks_cluster_name
  cluster_version = var.kubernetes_version

  vpc_id     = aws_vpc.this.id
  subnet_ids = [for s in aws_subnet.private : s.id]

  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = false
  enable_irsa                     = true
  cluster_enabled_log_types       = ["api", "audit", "authenticator"]

  enable_cluster_creator_admin_permissions = true

  eks_managed_node_groups = {
    system = {
      instance_types = ["m6i.large"]
      min_size       = 2
      max_size       = 3
      desired_size   = 2
      labels         = { pool = "system" }
    }
    apps = {
      instance_types = var.app_node_instance_types
      min_size       = var.app_nodes_min
      max_size       = var.app_nodes_max
      desired_size   = var.app_nodes_min
      labels         = { pool = "apps" }
    }
  }
}
