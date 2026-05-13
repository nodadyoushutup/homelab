locals {
  # Always manage a single core project `homelab` for all homelab images
  # (`registry/homelab/<repo>:<tag>`). Entries in var.projects with the same name
  # override these defaults; additional project names extend the map.
  default_homelab_project = {
    name                        = "homelab"
    public                      = false
    vulnerability_scanning      = true
  }

  project_specs = merge(
    { homelab = local.default_homelab_project },
    { for project in var.projects : project.name => project },
  )

  user_specs = {
    for user in var.users :
    user.username => user
  }

  project_member_specs = {
    for member in var.project_members :
    "${member.project_name}:${member.user_name}" => member
  }

  robot_account_specs = {
    for robot in var.robot_accounts :
    robot.name => robot
  }
}

resource "harbor_config_system" "this" {
  count = var.manage_system_config ? 1 : 0

  read_only                    = try(var.system_config.read_only, null)
  project_creation_restriction = try(var.system_config.project_creation_restriction, null)
  robot_name_prefix            = try(var.system_config.robot_name_prefix, null)
  robot_token_expiration       = try(var.system_config.robot_token_expiration, null)
  scanner_skip_update_pulltime = try(var.system_config.scanner_skip_update_pulltime, null)
  skip_audit_log_database      = try(var.system_config.skip_audit_log_database, null)
  storage_per_project          = try(var.system_config.storage_per_project, null)
  audit_log_forward_endpoint   = try(var.system_config.audit_log_forward_endpoint, null)

  dynamic "banner_message" {
    for_each = try(var.system_config.banner_message, null) == null ? [] : [var.system_config.banner_message]

    content {
      message   = banner_message.value.message
      type      = try(banner_message.value.type, null)
      closable  = try(banner_message.value.closable, null)
      from_date = try(banner_message.value.from_date, null)
      to_date   = try(banner_message.value.to_date, null)
    }
  }
}

resource "harbor_project" "projects" {
  for_each = local.project_specs

  name                        = each.value.name
  public                      = try(each.value.public, false)
  vulnerability_scanning      = try(each.value.vulnerability_scanning, true)
  auto_sbom_generation        = try(each.value.auto_sbom_generation, null)
  enable_content_trust        = try(each.value.enable_content_trust, null)
  enable_content_trust_cosign = try(each.value.enable_content_trust_cosign, null)
  deployment_security         = try(each.value.deployment_security, null)
  cve_allowlist               = try(each.value.cve_allowlist, null)
  proxy_speed_kb              = try(each.value.proxy_speed_kb, null)
  storage_quota               = try(each.value.storage_quota, null)
  # Default true so removing a project from tfvars can destroy non-empty Harbor projects.
  force_destroy               = try(each.value.force_destroy, true)
}

resource "harbor_user" "users" {
  for_each = local.user_specs

  username  = each.value.username
  email     = each.value.email
  full_name = each.value.full_name
  password  = each.value.password
  admin     = try(each.value.admin, false)
  comment   = try(each.value.comment, null)
}

resource "harbor_project_member_user" "members" {
  for_each = local.project_member_specs

  project_id = tostring(harbor_project.projects[each.value.project_name].project_id)
  user_name  = each.value.user_name
  role       = each.value.role

  depends_on = [
    harbor_user.users,
    harbor_project.projects,
  ]
}

resource "null_resource" "delete_default_library_project" {
  count = var.delete_default_library ? 1 : 0

  triggers = {
    url        = var.provider_config.harbor.url
    always_run = timestamp()
  }

  provisioner "local-exec" {
    interpreter = ["/usr/bin/env", "bash", "-c"]
    environment = {
      HARBOR_URL      = var.provider_config.harbor.url
      HARBOR_USER     = var.provider_config.harbor.username
      HARBOR_PASS     = try(var.provider_config.harbor.password, "")
      HARBOR_INSECURE = try(var.provider_config.harbor.insecure, false) ? "1" : "0"
    }
    command = <<-EOT
      set -euo pipefail

      curl_args=(--silent --show-error --user "$HARBOR_USER:$HARBOR_PASS" --header "Accept: application/json")
      if [[ "$${HARBOR_INSECURE:-0}" == "1" ]]; then
        curl_args+=(--insecure)
      fi

      lookup_url="$HARBOR_URL/api/v2.0/projects?name=library&exact=true"
      list_resp="$(curl "$${curl_args[@]}" --fail "$lookup_url")"
      proj_id="$(printf '%s' "$list_resp" | python3 -c "import json,sys; data=json.loads(sys.stdin.read() or '[]'); print(data[0]['project_id'] if data else '')")"

      if [[ -z "$proj_id" ]]; then
        echo "Harbor 'library' project not present; nothing to delete."
        exit 0
      fi

      echo "Deleting Harbor default 'library' project (id=$proj_id)..."
      delete_url="$HARBOR_URL/api/v2.0/projects/$proj_id"
      tmp_out="$(mktemp -t harbor-delete-library-XXXXXX)"
      trap 'rm -f "$tmp_out"' EXIT

      http_code="$(curl "$${curl_args[@]}" --output "$tmp_out" --write-out '%%{http_code}' --request DELETE "$delete_url" || true)"

      case "$http_code" in
        200|204)
          echo "Library project deleted (http=$http_code)."
          ;;
        404)
          echo "Library project already gone (http=$http_code)."
          ;;
        412)
          echo "[ERR] Harbor refused to delete 'library' (http=412): project still has repositories. Empty it or relocate its contents, then re-run." >&2
          cat "$tmp_out" >&2 || true
          exit 1
          ;;
        *)
          echo "[ERR] Unexpected response deleting 'library' (http=$http_code)." >&2
          cat "$tmp_out" >&2 || true
          exit 1
          ;;
      esac
    EOT
  }
}

resource "harbor_robot_account" "accounts" {
  for_each = local.robot_account_specs

  name        = each.value.name
  level       = each.value.level
  description = try(each.value.description, null)
  disable     = try(each.value.disable, null)
  duration    = try(each.value.duration, null)
  secret      = try(each.value.secret, null)

  dynamic "permissions" {
    for_each = try(each.value.permissions, [])

    content {
      kind      = permissions.value.kind
      namespace = permissions.value.namespace

      dynamic "access" {
        for_each = permissions.value.access

        content {
          action   = access.value.action
          resource = access.value.resource
          effect   = try(access.value.effect, null)
        }
      }
    }
  }

  depends_on = [harbor_project.projects]
}
