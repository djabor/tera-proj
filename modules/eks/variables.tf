locals {
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)
  vpc_cidr = "10.0.0.0/16"
}

variable "clusters" {
  type = map(any)
  default = {
    root-eks = {
      root = true
    }
  }
}

variable "cluster_version" {
  type = string
  default = "1.24"
}

variable "region" {
  type = string
  default = "us-east-1"
}

data "aws_eks_cluster_auth" "cluster_auth" {
  for_each = module.eks
  name = each.value.cluster_name
}

data "aws_availability_zones" "available" {}
data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}