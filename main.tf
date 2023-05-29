################################################################################
# Setup
################################################################################

module eks {
  source = "./modules/eks"
  clusters = local.clusters
  cluster_version = local.cluster_version
  region = local.region
}