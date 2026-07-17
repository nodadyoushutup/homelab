# outputs.tf
# Exported scrape URLs and Prometheus job snippet for prometheus-pve-exporter.

output "metrics_url" {
  description = "Exporter self-metrics endpoint on the published host port."
  value       = "http://${local.endpoint_host}:${local.published_port}/metrics"
}

output "pve_scrape_url" {
  description = "Example PVE metrics URL (Prometheus uses /pve with relabeling)."
  value       = "http://${local.endpoint_host}:${local.published_port}/pve?target=${local.pve_targets[0]}&cluster=1&node=1"
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
      for target in local.pve_targets : {
        targets = [target]
        labels = {
          platform    = "proxmox"
          node_domain = "hypervisor"
          hostname    = "pve"
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
        replacement  = "${local.endpoint_host}:${local.published_port}"
      },
    ]
  }
}
