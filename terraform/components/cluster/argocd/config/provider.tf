# provider.tf
# S3 remote state and Argo CD provider for the Argo CD config stack.

terraform {
  backend "s3" {
    key = "argocd-config.tfstate"
  }

  required_providers {
    argocd = {
      source  = "argoproj-labs/argocd"
      version = "7.15.0"
    }
  }
}

provider "argocd" {
  server_addr = local.argocd_server_host
  auth_token  = local.argocd_api_token
  insecure    = local.argocd_insecure_skip_verify
  grpc_web    = true
}
