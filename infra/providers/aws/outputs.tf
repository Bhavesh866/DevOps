output "vpc_id" { value = aws_vpc.this.id }
output "private_subnet_ids" { value = [for s in aws_subnet.private : s.id] }
output "public_subnet_ids" { value = [for s in aws_subnet.public : s.id] }
output "cluster_name_input" {
  value       = var.eks_cluster_name
  description = "Reserved input; EKS is not created by this starter."
}
