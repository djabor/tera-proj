################################################################################
# Providers
################################################################################

provider "aws" {
  region = var.region
}

provider "kubernetes" {
  alias                   = "root-eks"
  host                    = module.eks.root-eks.cluster_endpoint
  cluster_ca_certificate  = base64decode(module.eks.root-eks.cluster_certificate_authority_data)
  token                   = data.aws_eks_cluster_auth.cluster_auth["root-eks"].token
}

provider "kubernetes" {
  alias                   = "app-eks-1"
  host                    = module.eks.app-eks-1.cluster_endpoint
  cluster_ca_certificate  = base64decode(module.eks.app-eks-1.cluster_certificate_authority_data)
  token                   = data.aws_eks_cluster_auth.cluster_auth["app-eks-1"].token
}

# provider "kubernetes" {
#   alias                   = "app-eks-2"
#   host                    = module.eks.app-eks-2.cluster_endpoint
#   cluster_ca_certificate  = base64decode(module.eks.app-eks-2.cluster_certificate_authority_data)
#   token                   = data.aws_eks_cluster_auth.cluster_auth["app-eks-2"].token
# }

provider "helm" {
  alias = "root-eks"
  kubernetes {
    host                   = module.eks.root-eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.root-eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.cluster_auth["root-eks"].token
  }
}

provider "helm" {
  alias = "app-eks-1"
  kubernetes {
    host                    = module.eks.app-eks-1.cluster_endpoint
    cluster_ca_certificate  = base64decode(module.eks.app-eks-1.cluster_certificate_authority_data)
    token                   = data.aws_eks_cluster_auth.cluster_auth["app-eks-1"].token
  }
}

# provider "helm" {
#   alias = "app-eks-2"
#   kubernetes {
#     host                    = module.eks.app-eks-2.cluster_endpoint
#     cluster_ca_certificate  = base64decode(module.eks.app-eks-2.cluster_certificate_authority_data)
#     token                   = data.aws_eks_cluster_auth.cluster_auth["app-eks-2"].token
#   }
# }

# provider "argocd" {
#   server_addr               = "adba273505f914fc38170f8edc49cb76-64955571.us-east-1.elb.amazonaws.com:443"
#   username                  = "admin"
#   password                  = random_password.argocd.result
# }

# provider "argocd" {
#   core = true
# }