# Grafana Loki Logs Plan

## Goal
Add Loki as a Grafana datasource and publish starter dashboards so Swarm logs are visible in Grafana immediately.

## Scope
- Update `terraform/swarm/grafana/config/main.tf`:
  - add `grafana_data_source.loki`
  - add a `Logs` folder
  - register a new Loki dashboard resource with file-hash replacement trigger
- Add dashboard JSON:
  - `terraform/swarm/grafana/config/dashboards/loki-swarm-logs-overview.json`
  - add a `service` variable sourced from Loki `swarm_service` labels
- Apply Grafana config pipeline.

## Validation Checklist
- [x] Loki datasource exists in Grafana with UID `loki`
- [x] Logs folder exists in Grafana
- [x] `Loki Swarm Logs Overview` dashboard exists in Grafana
- [x] Dashboard panels return data from `{cluster="swarm"}`
- [x] Dashboard has a working `Service` filter variable (`$service`)
  - Implemented with Loki variable query object (`stream` + `label`) and dashboard-load refresh

## Completion
- [x] Terraform apply completed in `terraform/swarm/grafana/config`
