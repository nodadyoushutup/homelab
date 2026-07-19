# variables.tf
# External input contract for the Grafana config slice.

variable "grafana" {
  description = "Grafana provider login (config-id terraform/providers/grafana); shared -var-file managed by the homelab-config web app."
  type = object({
    url  = string
    auth = string
  })
  sensitive = true
}

variable "datasources" {
  description = "Grafana data source definitions. uid must match dashboard JSON datasource references; uid prometheus is the canonical VictoriaMetrics query path."
  type = list(object({
    name       = string
    uid        = string
    type       = string
    url        = string
    is_default = optional(bool, false)
    json_data  = optional(map(any))
  }))

  validation {
    condition = alltrue([
      for datasource in var.datasources :
      datasource.uid != "prometheus" || datasource.url == "http://victoriametrics:8428"
    ])
    error_message = "The prometheus datasource UID must use the canonical VictoriaMetrics URL http://victoriametrics:8428."
  }
}

