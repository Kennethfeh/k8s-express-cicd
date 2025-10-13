output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.eks_cluster.name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = aws_eks_cluster.eks_cluster.endpoint
}

output "cluster_security_group_id" {
  description = "Security group ID attached to EKS cluster"
  value       = aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id
}

output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster OIDC Issuer"
  value       = aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer
}

output "cluster_version" {
  description = "EKS cluster version"
  value       = aws_eks_cluster.eks_cluster.version
}

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.app_ecr.repository_url
}

output "node_group_name" {
  description = "EKS node group name"
  value       = aws_eks_node_group.eks_node_group.node_group_name
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.eks_vpc.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = aws_subnet.eks_private_subnets[*].id
}

output "public_subnet_ids" {
  description = "Public subnet IDs" 
  value       = aws_subnet.eks_public_subnets[*].id
}

output "kubeconfig_command" {
  description = "Command to update kubeconfig"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.eks_cluster.name}"
}
