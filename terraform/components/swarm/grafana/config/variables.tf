# variables.tf
# External input contract for the Grafana config slice.

variable "provider_config" {
  description = "Grafana API URL and credentials for this config slice."
  type = object({
    url  = string
    auth = string
  })
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

