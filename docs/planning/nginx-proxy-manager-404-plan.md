# Nginx Proxy Manager default 404 page plan

This plan tracks replacing the NPM global default site with a custom dark 404 page for unknown hosts.

## Stage 0 - scope lock

- [x] Confirm target behavior:
  - unknown hostnames should render a custom branded 404 page
  - default site mode should be managed declaratively in Terraform
  Mark complete when: Terraform code includes an explicit `nginxproxymanager_settings` default-site configuration.

## Stage 1 - implementation

- [x] Add custom HTML/CSS payload for the 404 page in the NPM config stack.
  Mark complete when: Terraform has a reusable local value for the page markup.
- [x] Set NPM global `default_site` to use custom HTML.
  Mark complete when: Terraform includes `nginxproxymanager_settings` with `default_site.page = "html"`.

## Stage 2 - validation

- [x] Run formatting and a Terraform plan for `terraform/swarm/nginx_proxy_manager/config`.
  Mark complete when: plan succeeds and shows expected settings update without destructive changes.

## Implementation notes

- Date: 2026-03-08
- Added `default-site-404.html.tftpl` and wired it through `templatefile(...)` to `nginxproxymanager_settings.default_site` in:
  - `terraform/swarm/nginx_proxy_manager/config/main.tf`
- Legacy/module cleanup:
  - Removed module usage from `terraform/swarm/nginx_proxy_manager/config/main.tf`.
  - Removed built-in legacy fallback config from stack code; `config` is now required from tfvars.
  - Converted stack to direct resources (`nginxproxymanager_certificate_letsencrypt`, `nginxproxymanager_proxy_host`, etc.) in stack `main.tf`.
  - Migrated existing state addresses from `module.nginx_proxy_manager_config.*` to root resource addresses via `terraform state mv`.
- Validation and rollout evidence:
  - `terraform validate` passed.
  - `terraform plan` showed only one change: create `nginxproxymanager_settings.default_site`.
  - `terraform apply` completed: `Apply complete! Resources: 1 added, 0 changed, 0 destroyed.`
  - Unknown-host check:
    - `curl -H 'Host: definitely-not-real-subdomain.nodadyoushutup.com' http://192.168.1.26/` returned the custom dark page content.
