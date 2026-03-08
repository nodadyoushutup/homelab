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

locals {
  argocd_server_host = trimsuffix(
    trimprefix(
      trimprefix(var.argocd_base_url, "https://"),
      "http://",
    ),
    "/",
  )
}

provider "argocd" {
  server_addr = local.argocd_server_host
  auth_token  = var.argocd_api_token
  insecure    = var.argocd_insecure_skip_verify
  grpc_web    = true
}
