output "metrics_urls" {
  description = "Prometheus scrape URLs per qBittorrent instance (host publish_mode on endpoint_host)."
  value = {
    for name, instance in var.instances :
    name => "http://${var.endpoint_host}:${instance.published_port}/metrics"
  }
}

output "qbittorrent_instance_count" {
  description = "Number of qBittorrent exporter services."
  value       = length(var.instances)
}

output "prometheus_static_targets" {
  description = "Host:port targets for prometheus.yaml static_configs."
  value       = [for instance in var.instances : "${var.endpoint_host}:${instance.published_port}"]
}

output "prometheus_scrape_static_configs" {
  description = "Per-instance static_configs entries (targets + labels) for prometheus.yaml job qbittorrent_exporter."
  value = [
    for name in local.instance_keys : {
      targets = ["${var.endpoint_host}:${var.instances[name].published_port}"]
      labels = {
        platform             = "docker"
        node_domain          = "swarm"
        hostname             = "swarm-wk-0.local"
        component            = "qbittorrent-exporter"
        qbittorrent_instance = name
        qbittorrent_type     = local.qbittorrent_instance_types[name]
      }
    }
  ]
}
