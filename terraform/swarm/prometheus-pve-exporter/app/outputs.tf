output "metrics_url" {
  description = "Exporter self-metrics endpoint on the published host port."
  value       = "http://${var.endpoint_host}:${var.published_port}/metrics"
}

output "pve_scrape_url" {
  description = "Example PVE metrics URL (Prometheus uses /pve with relabeling)."
  value       = "http://${var.endpoint_host}:${var.published_port}/pve?target=${var.pve_targets[0]}&cluster=1&node=1"
}

output "prometheus_scrape_config_snippet" {
  description = "Job fragment for prometheus.yaml (remote exporter pattern)."
  value = {
    job_name        = "pve"
    metrics_path    = "/pve"
    scrape_interval = "30s"
    scrape_timeout  = "25s"
    params = {
      module  = ["default"]
      cluster = ["1"]
      node    = ["1"]
    }
    static_configs = [
      for target in var.pve_targets : {
        targets = [target]
        labels = {
          platform    = "proxmox"
          node_domain = "hypervisor"
        }
      }
    ]
    relabel_configs = [
      {
        source_labels = ["__address__"]
        target_label  = "__param_target"
      },
      {
        source_labels = ["__param_target"]
        target_label  = "instance"
      },
      {
        target_label = "__address__"
        replacement  = "${var.endpoint_host}:${var.published_port}"
      },
    ]
  }
}
