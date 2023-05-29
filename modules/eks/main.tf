################################################################################
# Network
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 4.0"

  for_each = var.clusters

  name = each.key
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = {
    Blueprint  = each.key
    GithubRepo = "github.com/aws-ia/terraform-aws-eks-blueprints"
  }
}

################################################################################
# EKS
################################################################################


module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.12"

  for_each = var.clusters

  cluster_name                   = each.key
  cluster_version                = var.cluster_version
  cluster_endpoint_public_access = true

  # EKS Addons
  cluster_addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni    = {}
  }

  vpc_id     = module.vpc[each.key].vpc_id
  subnet_ids = module.vpc[each.key].private_subnets

  eks_managed_node_groups = {
    initial = {
      instance_types = each.value.root ? ["t3.large"] : ["t3.small"]

      min_size     = 1
      max_size     = 2
      desired_size = each.value.root ? 2 : 1
    }
  }

  tags = {
    Blueprint  = each.key
    GithubRepo = "github.com/aws-ia/terraform-aws-eks-blueprints"
  }
}

################################################################################
# Kubernetes Addons
################################################################################

module "kube_addons" {
  # This example shows how to set default ArgoCD Admin Password using SecretsManager with Helm Chart set_sensitive values.
  providers = {
    kubernetes = kubernetes.root-eks
    helm = helm.root-eks
  }

  source = "../eks-blueprints/modules/kubernetes-addons"

  eks_cluster_id        = module.eks["root-eks"].cluster_name
  eks_cluster_endpoint  = module.eks["root-eks"].cluster_endpoint
  eks_oidc_provider     = module.eks["root-eks"].oidc_provider
  eks_cluster_version   = module.eks["root-eks"].cluster_version
  
  enable_aws_load_balancer_controller = true
  enable_ingress_nginx  = true
  ingress_nginx_helm_config = {
    name              = "ingress-nginx"
    namespace         = "ingress-nginx"
    version           = "4.2.3"
    repository        = "https://kubernetes.github.io/ingress-nginx"
    create_namespace  = true
    set = [{
      name = "controller.service.type"
      value = "LoadBalancer"
    }]
  }

  enable_argocd         = true
  argocd_helm_config = {
    name                = "argo-cd"
    chart               = "argo-cd"
    repository          = "https://argoproj.github.io/argo-helm"
    version             = "5.34.6"
    namespace           = "argocd"
    timeout             = "1200"
    create_namespace    = true
    server = {
      ingress = {
        ingress_class_name  = "nginx"
        enabled             = true
        https               = true
      }
    }
    set_sensitive = [
    {
      name    = "configs.secret.argocdServerAdminPassword"
      value   = bcrypt_hash.argo.id
    }
    ]
    set = [{
      name = "configs.params.applicationsetcontroller\\.enable\\.progressive\\.syncs"
      value = true
    }]
  }

  tags = {
    Blueprint  = "root-eks"
    GithubRepo = "github.com/aws-ia/terraform-aws-eks-blueprints"
  }
}

resource "kubernetes_ingress_v1" "argocd_ingress" {

  provider = kubernetes.root-eks
  metadata {
    name      = "argocd-ingress"
    namespace = "argocd"
    annotations = {
      "nginx.ingress.kubernetes.io/force-ssl-redirect"  = "true"
      "nginx.ingress.kubernetes.io/backend-protocol"    = "HTTPS"
    }
  }

  spec {
    ingress_class_name = "nginx"
    rule {
      http {
        path {
          path = "/"
          backend {
            service {
              name = "argo-cd-argocd-server"
              port {
                 name = "https"
               }
            }
          }
        }
      }
    }
    tls {
      secret_name = "argocd-secret"
    }
  }
  depends_on = [ module.kube_addons ]
}

################################################################################
# ArgoCD Configuration
################################################################################

resource "random_password" "argocd" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "bcrypt_hash" "argo" {
  cleartext = random_password.argocd.result
}

#tfsec:ignore:aws-ssm-secret-use-customer-key
resource "aws_secretsmanager_secret" "argocd" {
  name                    = "argocd"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "argocd" {
  secret_id     = aws_secretsmanager_secret.argocd.id
  secret_string = random_password.argocd.result
}

resource "kubernetes_namespace" "argocd" {
  provider = kubernetes.app-eks-1
  metadata {
    name = "argocd"
  }
}

resource "kubernetes_service_account" "argocd_manager" {
  provider = kubernetes.app-eks-1

  metadata {
    name      = "argocd-manager-sa"
    namespace = "argocd"
  }
  depends_on = [ kubernetes_namespace.argocd ]
}

resource "kubernetes_cluster_role_binding" "argocd_manager" {
  provider = kubernetes.app-eks-1
  metadata {
    name = "argocd-manager-role-binding"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.argocd_manager.metadata[0].name
    namespace = kubernetes_service_account.argocd_manager.metadata[0].namespace
  }
  depends_on = [kubernetes_service_account.argocd_manager]
}

resource "kubernetes_secret" "argocd_manager" {
  provider = kubernetes.app-eks-1
  metadata {
    name        = "argocd-manager-sa-token"
    namespace   = "argocd"
    annotations = {
      "kubernetes.io/service-account.name" = "argocd-manager-sa"
    }
  }
  type = "kubernetes.io/service-account-token"
  depends_on = [kubernetes_service_account.argocd_manager]
}

data "kubernetes_secret" "argocd_manager" {
  provider = kubernetes.app-eks-1
  metadata {
    name = "argocd-manager-sa-token"
    namespace = "argocd"
  }
  depends_on = [ kubernetes_secret.argocd_manager ]
}

data "kubernetes_ingress_v1" "argocd_server" {
  provider = kubernetes.root-eks
  metadata {
    name      = "argocd-ingress"
    namespace = "argocd"   # replace with the correct namespace if not 'argocd'
  }
  depends_on = [ kubernetes_ingress_v1.argocd_ingress ]
}

# Configure the ArgoCD provider to connect to the ArgoCD API server
provider "argocd" {
  server_addr = "${data.kubernetes_ingress_v1.argocd_server.status[0].load_balancer[0].ingress[0].hostname}:443"
  username = "admin"
  password = random_password.argocd.result
  insecure = true
}

data "aws_eks_cluster_auth" "app_cluster" {
  name = "app-eks-1"
}

resource "argocd_cluster" "eks" {
  for_each = { 
    for key,cluster_config in var.clusters : key => cluster_config
    if cluster_config.root == false
  }

  # server     = format("https://%s", module.eks[each.key].cluster_endpoint)
  server     = module.eks[each.key].cluster_endpoint
  name       = module.eks[each.key].cluster_name

  config {
    bearer_token = data.kubernetes_secret.argocd_manager.data["token"]
    tls_client_config {
      insecure = true
    }
  }

  depends_on = [
    kubernetes_cluster_role_binding.argocd_manager,
    kubernetes_secret.argocd_manager
  ]
}

resource "argocd_application_set" "list" {
  metadata {
    name = "list"
  }
  spec {
    generator {
      list {
        elements = [
          for index, cluster in module.eks: {
            cluster = cluster.cluster_name
            url = "${cluster.cluster_name != "root-eks" ? cluster.cluster_endpoint : "https://kubernetes.default.svc"}"
          }
        ]
      }
      # This feature is no yet supported throught the terraform argocd provider
      # as the feature is still in alpha
      # migrating the applicationset definition to the git repository would have
      # solved this issue. Due to time constraints i was not able to migrate.
      # I left the definition as a theoretical concept.
      # strategy {
      #   type = "RollingSync"
      #   rolling_sync {
      #     steps = [
      #       {
      #         math_expressions = [
      #           { 
      #             key = "env_label"
      #             operator = "In"
      #             values = [
      #               "app-eks-1"
      #             ]
      #           }
      #         ]
      #       },
      #       {
      #         math_expressions = [
      #           { 
      #             key = "env_label"
      #             operator = "In"
      #             values = [
      #               "root-eks"
      #             ]
      #           }
      #         ]
      #       }
      #     ]
      #   }
      # }
    }

    template {
      metadata {
        name = "{{cluster}}-nginx"
        # this label would the matched selector label using rolling sync strategy
        # label = {
        #   env_label = "{{cluster}}"
        # }
      }
      spec {
        project = "default"

        source {
          repo_url        = "https://github.com/djabor/tera-gitops.git"
          target_revision = "1.0.0"
          path = "charts/nginx"
          helm {
            value_files = [
              "values/{{cluster}}/nginx-values.yaml"
            ]
          }
        }
        destination {
          server    = "{{url}}"
          namespace = "nginx"
        }
        sync_policy {
          automated {
            prune = true
          }
          sync_options = [
            "PruneLast=true",
            "CreateNamespace=true"
          ]
        }
      }
    }
  }

  depends_on = [ argocd_cluster.eks ]
}
output "argocd_server_ingress_status" {
  value = data.kubernetes_ingress_v1.argocd_server.status
}

