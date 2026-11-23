#!/usr/bin/env bash
# Run a golden-k8 playbook against the cluster in build/contract.json.
#
#   scripts/playbook.sh bootstrap [--check-idempotent]
#   scripts/playbook.sh smoke
#
# --check-idempotent runs the playbook a second time and fails unless that
# run reports changed=0.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/ansible" || exit 1

playbook="${1:?usage: playbook.sh bootstrap|smoke [--check-idempotent]}"
[ -f "playbooks/$playbook.yml" ] || { echo "playbook: no such playbook: $playbook" >&2; exit 1; }
contract="$ROOT/build/contract.json"
[ -f "$contract" ] || { echo "$playbook: no build/contract.json (run: make infra-up ENV=...)" >&2; exit 1; }
# Pin every tool (kubectl, helm, kubernetes client) to the golden-k8 cluster so
# nothing can fall back to the user's default kubeconfig/current-context.
KUBECONFIG="$(yq -r '.kubeconfig_path' "$contract")"
export KUBECONFIG K8S_AUTH_KUBECONFIG="$KUBECONFIG"
K8S_AUTH_CONTEXT="$(yq -r '.kube_context' "$contract")"
export K8S_AUTH_CONTEXT
# Helm gets its own config, cache and data under build/: the user's Helm repos,
# plugins and registry logins can't leak in.
export HELM_CONFIG_HOME="$ROOT/build/helm/config" HELM_CACHE_HOME="$ROOT/build/helm/cache" HELM_DATA_HOME="$ROOT/build/helm/data"

# Ansible runtime: locked Python env from ansible/pyproject.toml + uv.lock.
uvx_ansible() { uv run --project "$ROOT/ansible" --locked --quiet "$@"; }

uvx_ansible ansible-galaxy collection install -r requirements.yml -p collections >/dev/null

run() { uvx_ansible ansible-playbook "playbooks/$playbook.yml" -e "golden_build_dir=$ROOT/build"; }

run
if [ "${2:-}" = "--check-idempotent" ]; then
  echo "$playbook: second run (idempotency check)"
  out="$(run | tee /dev/stderr)"
  recap="$(printf '%s\n' "$out" | grep -E '^localhost +:')"
  if ! printf '%s\n' "$recap" | grep -Eq 'changed=0 .*failed=0'; then
    echo "$playbook: not idempotent: $recap" >&2
    exit 1
  fi
  echo "$playbook: idempotent (changed=0)"
fi
