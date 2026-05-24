variable "provider_config" {
  description = "Grafana API URL and credentials for this config slice."
  type = object({
    url  = string
    auth = string
  })
}

variable "datasources" {
  description = "Grafana data source definitions. uid must match dashboard JSON datasource references."
  type = list(object({
    name       = string
    uid        = string
    type       = string
    url        = string
    is_default = optional(bool, false)
    json_data  = optional(map(any))
  }))
}

