#!/usr/bin/env bash
# Run the platform bootstrap playbook against the cluster in build/contract.json.
#
#   scripts/bootstrap.sh [--check-idempotent]
#
# --check-idempotent runs the playbook a second time and fails unless that
# run reports changed=0.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/ansible" || exit 1

contract="$ROOT/build/contract.json"
[ -f "$contract" ] || { echo "bootstrap: no build/contract.json (run: make infra-up ENV=...)" >&2; exit 1; }
# Pin every tool (kubectl, helm, kubernetes client) to the golden-k8 cluster so
# nothing can fall back to the user's default kubeconfig/current-context.
KUBECONFIG="$(yq -r '.kubeconfig_path' "$contract")"
export KUBECONFIG K8S_AUTH_KUBECONFIG="$KUBECONFIG"
K8S_AUTH_CONTEXT="$(yq -r '.kube_context' "$contract")"
export K8S_AUTH_CONTEXT

ansible-galaxy collection install -r requirements.yml -p collections >/dev/null

run() { ansible-playbook playbooks/bootstrap.yml -e "golden_build_dir=$ROOT/build"; }

run
if [ "${1:-}" = "--check-idempotent" ]; then
  echo "bootstrap: second run (idempotency check)"
  out="$(run | tee /dev/stderr)"
  recap="$(printf '%s\n' "$out" | grep -E '^localhost +:')"
  if ! printf '%s\n' "$recap" | grep -Eq 'changed=0 .*failed=0'; then
    echo "bootstrap: not idempotent: $recap" >&2
    exit 1
  fi
  echo "bootstrap: idempotent (changed=0)"
fi
