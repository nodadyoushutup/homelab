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

locals {
  grafana_provider_url = coalesce(
    try(var.provider_config.grafana.url, null),
    "http://localhost:3000"
  )

  grafana_provider_username = coalesce(
    try(var.provider_config.grafana.username, null),
    "admin"
  )

  grafana_provider_password = coalesce(
    try(var.provider_config.grafana.password, null),
    ""
  )

  grafana_provider_auth = coalesce(
    try(var.provider_config.grafana.api_token, null),
    format("%s:%s", local.grafana_provider_username, local.grafana_provider_password)
  )
}

provider "grafana" {
  url  = local.grafana_provider_url
  auth = local.grafana_provider_auth
}
