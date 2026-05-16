locals {
  argocd_server_host = trimsuffix(
    trimprefix(
      trimprefix(var.argocd_base_url, "https://"),
      "http://",
    ),
    "/",
  )
}
