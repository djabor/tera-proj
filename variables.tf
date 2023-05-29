locals {
  clusters = {
    root-eks = {
      root = true
    }
    app-eks-1 = {
      root = false
    }
  }
  region = "eu-central-1"

  cluster_version = "1.24"
}