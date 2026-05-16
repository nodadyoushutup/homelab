output "metrics_url" {
  description = "Prometheus scrape URL on the Swarm ingress host."
  value       = "http://${var.endpoint_host}:${var.published_port}/metrics"
}

output "qbittorrent_instance_count" {
  description = "Number of configured qBittorrent targets."
  value       = length(local.qbittorrent_hosts)
}
