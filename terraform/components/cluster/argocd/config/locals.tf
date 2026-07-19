# locals.tf
# Single source of truth for the Argo CD provider/application values (resources read local.* only).

locals {
  argocd_api_token            = var.argocd.api_token
  argocd_insecure_skip_verify = try(var.argocd.insecure_skip_verify, false)

  argocd_server_host = trimsuffix(
    trimprefix(
      trimprefix(var.argocd.base_url, "https://"),
      "http://",
    ),
    "/",
  )
}
