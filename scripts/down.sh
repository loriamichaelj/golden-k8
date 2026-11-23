#!/usr/bin/env bash
# Tear down an environment (make down).
#
#   scripts/down.sh [build/config.json] [--confirm-existing]
#
# provider local:    destroy the kind cluster.
# provider existing: remove only what golden-k8 installed (Gateway, Helm
#                    releases, namespaces labelled golden-k8/managed=true),
#                    then forget the Terraform state. The cluster stays.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
config="${1:-$ROOT/build/config.json}"
shift || true

provider="$(yq -r '.spec.provider' "$config")"
if [ "$provider" = existing ] && [ -f "$ROOT/build/contract.json" ]; then
  "$ROOT/scripts/playbook.sh" teardown "$@"
fi
"$ROOT/scripts/infra.sh" down "$config"
