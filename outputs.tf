output "configure_root_eks" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value = {
    for k, cluster in module.eks.eks_config : k => "aws eks --region ${local.region} update-kubeconfig --name ${cluster.cluster_name}"
  }
}

output "argocd_server_ingress_status" {
  value = module.eks.argocd_server_ingress_status
}