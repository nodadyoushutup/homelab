variable "harbor_hostname" {
  description = "Public Harbor hostname (used by harbor-prepare to render component env and URLs)."
  type        = string
}


variable "harbor_admin_password" {
  description = "Initial Harbor admin password. Used by harbor-prepare; align config.tfvars provider password after first install."
  type        = string
  sensitive   = true
}


variable "harbor_db_password" {
  description = "PostgreSQL password for Harbor's registry database."
  type        = string
  sensitive   = true
}


variable "harbor_external_url" {
  description = "Optional public URL when Harbor sits behind an edge proxy (for example https://harbor.example.com)."
  type        = string
  default     = ""
}


variable "enable_trivy" {
  description = "When true, harbor-prepare runs with --with-trivy."
  type        = bool
  default     = true
}


variable "prepare_image" {
  description = "harbor-prepare image used by the app pipeline before Terraform apply."
  type        = string
  default     = "ghcr.io/nodadyoushutup/harbor-prepare:0.0.3@sha256:5b319c300934aa66671316570afae4c4b05de42d287ac688e311693fefa6eb36"
}


variable "harbor_data_path" {
  description = "Absolute host path on the swarm node for Harbor persistent runtime data."
  type        = string
  default     = "/mnt/eapp/harbor-manual/data"
}


variable "harbor_install_path" {
  description = "Absolute host path on the swarm node where Harbor install/config files exist."
  type        = string
  default     = "/mnt/eapp/harbor-manual/harbor"
}


variable "harbor_log_path" {
  description = "Absolute host path on the swarm node for Harbor rsyslog log files."
  type        = string
  default     = "/mnt/eapp/harbor-manual/log"
}


variable "images" {
  description = "Container image references for Harbor runtime components."
  type = object({
    log           = string
    registry      = string
    registryctl   = string
    db            = string
    core          = string
    portal        = string
    jobservice    = string
    redis         = string
    proxy         = string
    trivy_adapter = string
  })
  default = {
    log           = "ghcr.io/nodadyoushutup/harbor-log:0.0.3@sha256:3c825671396013959a14606341bfc028df49c71f1232d31829ac377b01101a8b"
    registry      = "ghcr.io/nodadyoushutup/harbor-registry-photon:0.0.3@sha256:39728942e0b127bfbb7302e70efdaaf005ebfb46b65dfd96975634b99a42f6aa"
    registryctl   = "ghcr.io/nodadyoushutup/harbor-registryctl:0.0.3@sha256:b5e58bea3ef309406eb4bcc47e36a3ecae394996511cf5775a4505ec9ed55624"
    db            = "ghcr.io/nodadyoushutup/harbor-db:0.0.3@sha256:f04806e9f06a6490cf2f3d5116ddf0ec742bb8f47a2787a322e8fe3c963c367b"
    core          = "ghcr.io/nodadyoushutup/harbor-core:0.0.3@sha256:e76c7c9b8d8b0df9ac70491b42b1a4a6098201840a45c62507f9445a1a385bb3"
    portal        = "ghcr.io/nodadyoushutup/harbor-portal:0.0.3@sha256:5c4d556f97360523f59a8d2c0198164e0ddc20ee38652ee7d30c33b056aaea3c"
    jobservice    = "ghcr.io/nodadyoushutup/harbor-jobservice:0.0.3@sha256:45a5e271dd301f1c069b26f4a631e0f7409ba1f4ccd0e894747f74ec6c1ad964"
    redis         = "ghcr.io/nodadyoushutup/harbor-redis-photon:0.0.3@sha256:a319fd20fb6d2a21d8edc6343c8bcf075e592c7f1c67c320e81039f876df2c0d"
    proxy         = "ghcr.io/nodadyoushutup/harbor-nginx-photon:0.0.3@sha256:486983aaf462f9482452693b53ea216d981289f62f74b078442a8ef8485c7241"
    trivy_adapter = "ghcr.io/nodadyoushutup/harbor-trivy-adapter-photon:0.0.3@sha256:1133526b6ca4cdcfd569fc4a976aefc023ecb32db08cb2beec6715b93f64644e"
  }
}


variable "log_syslog_published_port" {
  description = "Host-mode published port used by harbor-log syslog receiver (target 10514)."
  type        = number
  default     = 1514
}


variable "network_name" {
  description = "Overlay network name for Harbor services."
  type        = string
  default     = "harbor"
}


variable "proxy_published_port" {
  description = "Published Swarm port for Harbor HTTP ingress (nginx proxy target is 8080)."
  type        = number
  default     = 35080
}


variable "dns_nameservers" {
  description = "DNS nameservers for Swarm task dns_config."
  type        = list(string)
  sensitive   = true
}


variable "placement" {
  description = "Optional Swarm placement constraints and platforms."
  type = object({
    constraints = optional(list(string))
    platforms = optional(list(object({
      os           = string
      architecture = string
    })))
  })
  default = null
}


variable "swarm_docker_provider_config" {
  description = "Docker SSH host and registry_auths for the Swarm control plane."
  type        = any
}

