# provider.tf
# S3 remote state and Grafana provider for the Grafana config slice.

terraform {
  backend "s3" {
    key = "grafana-config.tfstate"
  }

  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "4.20.1"
    }
  }
}

provider "grafana" {
  url  = var.grafana.url
  auth = var.grafana.auth
}
