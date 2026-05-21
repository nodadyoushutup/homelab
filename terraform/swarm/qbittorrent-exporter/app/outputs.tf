output "metrics_urls" {
  description = "Prometheus scrape URLs per qBittorrent instance (host publish_mode on endpoint_host)."
  value = {
    for name, port in local.instance_ports :
    name => "http://${var.endpoint_host}:${port}/metrics"
  }
}

output "qbittorrent_instance_count" {
  description = "Number of qBittorrent exporter services."
  value       = length(local.qbittorrent_hosts)
}

output "prometheus_static_targets" {
  description = "Host:port targets for prometheus.yaml static_configs."
  value       = [for port in values(local.instance_ports) : "${var.endpoint_host}:${port}"]
}

output "prometheus_scrape_static_configs" {
  description = "Per-instance static_configs entries (targets + labels) for prometheus.yaml job qbittorrent_exporter."
  value = [
    for name in local.instance_keys : {
      targets = ["${var.endpoint_host}:${local.instance_ports[name]}"]
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
