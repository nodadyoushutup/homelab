"""Declarative specs for the single-object provider credential sections.

Each :class:`ProviderSpec` describes one Terraform provider whose login lives in
a shared ``.config/terraform/providers/<app>.tfvars`` file (config-id
``terraform/providers/<app>``), edited from its own homelab-config UI page. The
whole section - config render/parse, store, REST blueprint, template, JS, and
nav entry - is driven off these specs so adding a provider is a one-line spec.

``proxmox`` and ``docker`` are intentionally NOT listed here: they predate this
framework and keep their bespoke modules (proxmox is a single object like these;
docker mixes derived swarm providers with editable lists).
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

from homelab_config.paths import PROVIDERS_DIR


@dataclass(frozen=True)
class ProviderField:
    """One editable field on a provider credentials form.

    ``type`` is ``"string"``, ``"bool"``, or ``"int"``. ``optional`` string/int
    fields are omitted from the rendered tfvars when empty (so the Terraform
    ``optional(...)`` object attributes fall back to their defaults); required
    string fields always render (even when empty). ``default`` seeds bool fields.
    """

    name: str
    type: str = "string"
    label: str = ""
    secret: bool = False
    optional: bool = False
    default: bool = False
    placeholder: str = ""
    help: str = ""

    def public(self) -> dict:
        """Return a JSON-serializable view for templates and client JS."""
        return {
            "name": self.name,
            "type": self.type,
            "label": self.label or self.name.replace("_", " ").title(),
            "secret": self.secret,
            "optional": self.optional,
            "default": self.default,
            "placeholder": self.placeholder,
            "help": self.help,
        }


@dataclass(frozen=True)
class ProviderSpec:
    """A provider credentials section backed by ``providers/<app>.tfvars``."""

    key: str
    title: str
    icon: str
    tfvars_var: str
    summary: str
    fields: tuple[ProviderField, ...]
    app: str = ""
    # Sidebar group heading this provider's nav link renders under. Defaults to
    # the generic "Providers" group; set to place a provider elsewhere (e.g.
    # Argo CD lives under "Kubernetes").
    group: str = "Providers"

    @property
    def _app(self) -> str:
        return self.app or self.key

    @property
    def config_id(self) -> str:
        """Config-id used to resolve the shared file (``terraform/providers/<app>``)."""
        return f"terraform/providers/{self._app}"

    @property
    def tfvars_filename(self) -> str:
        return f"{self._app}.tfvars"

    @property
    def tfvars_path(self) -> Path:
        return PROVIDERS_DIR / self.tfvars_filename

    @property
    def tfvars_display(self) -> str:
        return f".config/terraform/providers/{self.tfvars_filename}"

    @property
    def store_key(self) -> str:
        return self.key

    @property
    def credentials_event(self) -> str:
        return f"{self.key}:credentials"

    @property
    def status_event(self) -> str:
        return f"{self.key}:status"

    def public(self) -> dict:
        """Return a JSON-serializable view for templates and client JS."""
        return {
            "key": self.key,
            "title": self.title,
            "icon": self.icon,
            "group": self.group,
            "tfvars_var": self.tfvars_var,
            "summary": self.summary,
            "config_id": self.config_id,
            "tfvars_filename": self.tfvars_filename,
            "tfvars_display": self.tfvars_display,
            "credentials_event": self.credentials_event,
            "status_event": self.status_event,
            "fields": [field.public() for field in self.fields],
        }


PROVIDER_SPECS: tuple[ProviderSpec, ...] = (
    ProviderSpec(
        key="cloudflare",
        title="Cloudflare",
        icon="fa-brands fa-cloudflare",
        tfvars_var="cloudflare",
        summary="API token for the cloudflare/cloudflare Terraform provider (DNS records).",
        fields=(
            ProviderField(
                name="api_token",
                label="API token",
                secret=True,
                placeholder="cloudflare API token",
                help="Scoped API token with DNS edit permission for the zone.",
            ),
        ),
    ),
    ProviderSpec(
        key="grafana",
        title="Grafana",
        icon="fa-solid fa-chart-line",
        tfvars_var="grafana",
        summary="API URL and token for the grafana/grafana Terraform provider.",
        fields=(
            ProviderField(
                name="url",
                label="URL",
                placeholder="http://grafana:3000",
                help="Grafana base URL reachable from the runner.",
            ),
            ProviderField(
                name="auth",
                label="Auth (API token)",
                secret=True,
                placeholder="grafana service-account token",
                help="Service-account token or api_key used for provider auth.",
            ),
        ),
    ),
    ProviderSpec(
        key="jenkins",
        title="Jenkins provider",
        icon="fa-brands fa-jenkins",
        tfvars_var="jenkins",
        summary="Controller URL and credentials for the taiidani/jenkins provider.",
        fields=(
            ProviderField(
                name="server_url",
                label="Server URL",
                placeholder="https://jenkins.example.com",
            ),
            ProviderField(name="username", label="Username", placeholder="admin"),
            ProviderField(
                name="password",
                label="Password / API token",
                secret=True,
                placeholder="api token",
            ),
        ),
    ),
    ProviderSpec(
        key="argocd",
        title="Argo CD",
        icon="fa-solid fa-diagram-project",
        group="Kubernetes",
        tfvars_var="argocd",
        summary="API URL and token for the argoproj-labs/argocd Terraform provider.",
        fields=(
            ProviderField(
                name="base_url",
                label="Base URL",
                placeholder="https://argocd.example.com",
                help="Full API base URL; the slice strips the scheme for server_addr.",
            ),
            ProviderField(
                name="api_token",
                label="API token",
                secret=True,
                placeholder="argocd auth token",
            ),
            ProviderField(
                name="insecure_skip_verify",
                type="bool",
                label="Insecure (skip TLS verify)",
                help="Skip TLS certificate verification for Argo CD API calls.",
            ),
        ),
    ),
    ProviderSpec(
        key="fortigate",
        title="FortiGate",
        icon="fa-solid fa-shield-halved",
        tfvars_var="fortigate",
        summary=(
            "Login for the fortinetdev/fortios provider. Set an API token OR a "
            "username + password."
        ),
        fields=(
            ProviderField(
                name="host",
                label="Host",
                placeholder="192.0.2.1",
                help="FortiGate management host or IP (no scheme).",
            ),
            ProviderField(
                name="port",
                type="int",
                label="Port",
                optional=True,
                placeholder="443",
                help="HTTPS management port; defaults to 443 when blank.",
            ),
            ProviderField(
                name="vdom",
                label="VDOM",
                optional=True,
                placeholder="root",
                help="Virtual domain; defaults to root when blank.",
            ),
            ProviderField(
                name="insecure",
                type="bool",
                label="Insecure (skip TLS verify)",
                default=True,
                help="Skip TLS certificate verification (defaults on).",
            ),
            ProviderField(
                name="api_token",
                label="API token",
                secret=True,
                optional=True,
                placeholder="REST API token",
            ),
            ProviderField(
                name="username", label="Username", optional=True, placeholder="admin"
            ),
            ProviderField(
                name="password", label="Password", secret=True, optional=True
            ),
        ),
    ),
    ProviderSpec(
        key="nginx_proxy_manager",
        title="Nginx Proxy Manager",
        icon="fa-solid fa-network-wired",
        tfvars_var="nginx_proxy_manager",
        summary="API URL and credentials for the Sander0542/nginxproxymanager provider.",
        fields=(
            ProviderField(
                name="url",
                label="URL",
                placeholder="http://nginx-proxy-manager:81",
            ),
            ProviderField(name="username", label="Username", placeholder="admin@example.com"),
            ProviderField(
                name="password", label="Password", secret=True, optional=True
            ),
            ProviderField(
                name="validate_tls",
                type="bool",
                label="Validate TLS",
                optional=True,
                help="Verify the NPM API TLS certificate.",
            ),
        ),
    ),
    ProviderSpec(
        key="vault",
        title="Vault",
        icon="fa-solid fa-vault",
        tfvars_var="vault",
        summary="Address and token for the hashicorp/vault Terraform provider.",
        fields=(
            ProviderField(
                name="address",
                label="Address",
                placeholder="https://vault.example.com:8200",
                help="Vault API address (VAULT_ADDR equivalent).",
            ),
            ProviderField(
                name="token",
                label="Token",
                secret=True,
                placeholder="vault token",
                help="Vault token used by the provider (VAULT_TOKEN equivalent).",
            ),
            ProviderField(
                name="skip_tls_verify",
                type="bool",
                label="Skip TLS verify",
                optional=True,
                help="Skip TLS certificate verification for Vault API calls.",
            ),
        ),
    ),
)

PROVIDER_SPECS_BY_KEY = {spec.key: spec for spec in PROVIDER_SPECS}


__all__ = ["ProviderField", "ProviderSpec", "PROVIDER_SPECS", "PROVIDER_SPECS_BY_KEY"]
