output "service_name" {
  description = "Docker Swarm service name."
  value       = docker_service.mcp_playwright.name
}

output "mcp_url" {
  description = "HTTP MCP endpoint URL on the Swarm ingress network."
  value       = "http://${var.endpoint_host}:${var.published_port}/mcp"
}

output "published_port" {
  description = "Published Swarm ingress port."
  value       = var.published_port
}

output "output_dir" {
  description = "Playwright MCP non-screenshot output directory."
  value       = var.output_dir
}

output "screenshot_dir" {
  description = "Playwright MCP screenshot output directory."
  value       = var.screenshot_dir
}
