#!/usr/bin/env bash
# Optional: export path to shared Swarm container DNS tfvars (dns_nameservers).
# swarm_pipeline.sh requires this file to exist (see homelab terraform/providers/dns.tfvars.example).
set -euo pipefail

TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${CONFIG_DIR:-${ROOT_DIR}/.config}}"
SWARM_DNS_PROVIDER_TFVARS="${SWARM_DNS_PROVIDER_TFVARS:-${TFVARS_HOME_DIR}/terraform/providers/dns.tfvars}"
export SWARM_DNS_PROVIDER_TFVARS
