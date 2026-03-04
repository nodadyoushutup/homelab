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
  url  = var.provider_config.grafana.url
  auth = var.provider_config.grafana.auth
}
