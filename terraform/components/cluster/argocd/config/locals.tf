# locals.tf
# Single source of truth for the Argo CD provider/application values (resources read local.* only).

locals {
  argocd_api_token            = var.argocd_api_token
  argocd_insecure_skip_verify = var.argocd_insecure_skip_verify

  argocd_server_host = trimsuffix(
    trimprefix(
      trimprefix(var.argocd_base_url, "https://"),
      "http://",
    ),
    "/",
  )
}
