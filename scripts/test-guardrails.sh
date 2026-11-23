#!/usr/bin/env bash
# Guardrail tests for provider existing: run the guardrails playbook against
# fake parameter files, contracts and kubeconfig snapshots. No cluster is ever
# contacted. Each case either passes or fails with an expected message.
#
#   scripts/test-guardrails.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

pass=0; fail=0
ok()  { pass=$((pass + 1)); printf '  \033[32mok\033[0m    %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  \033[31mFAIL\033[0m  %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/        /'; }

# case <name> <config context> <allowedContexts JSON> <contract context> <contract endpoint>
#      <snapshot "context=server" ...> <confirm> <expect: ok | message substring>
case_() {
  local name="$1" cfg_ctx="$2" allowed="$3" ctr_ctx="$4" endpoint="$5" snapshot="$6" confirm="$7" expect="$8"
  local dir="$tmp/$name"
  mkdir -p "$dir"

  printf 'apiVersion: golden.k8/v1alpha1\nkind: Environment\nmetadata:\n  name: guard\nspec:\n  provider: existing\n  cluster:\n    existing:\n      context: %s\n      allowedContexts: %s\n' \
    "$cfg_ctx" "$allowed" > "$dir/env.yaml"
  "$ROOT/scripts/config.sh" "$dir/env.yaml" "$dir/config.json" 2>/dev/null || { bad "$name" "fixture config invalid"; return; }

  {
    printf 'apiVersion: v1\nkind: Config\nclusters:\n'
    for entry in $snapshot; do printf '  - name: %s\n    cluster:\n      server: %s\n' "${entry%%=*}" "${entry#*=}"; done
    printf 'contexts:\n'
    for entry in $snapshot; do printf '  - name: %s\n    context:\n      cluster: %s\n      user: %s\n' "${entry%%=*}" "${entry%%=*}" "${entry%%=*}"; done
    printf 'users: []\n'
  } > "$dir/kubeconfig"

  cat > "$dir/contract.json" <<JSON
{"contract_version": "v1", "provider": "existing", "cluster_name": "golden-guard",
 "cluster_endpoint": "$endpoint", "kubeconfig_path": "$dir/kubeconfig", "kube_context": "$ctr_ctx",
 "storage_class": "", "gateway_service_type": "LoadBalancer", "gateway_node_port": null,
 "lb_annotations": {}, "network_id": "", "private_subnet_ids": []}
JSON

  local out status
  out="$(cd "$ROOT/ansible" && uv run --project "$ROOT/ansible" --locked --quiet \
    ansible-playbook playbooks/guardrails.yml -e "golden_build_dir=$dir" \
    -e "golden_contract_path=$dir/contract.json" -e "golden_confirm_existing=$confirm" 2>&1)"
  status=$?
  if [ "$expect" = ok ]; then
    if [ $status -eq 0 ]; then ok "$name passes"; else bad "$name should pass" "$out"; fi
  elif [ $status -ne 0 ] && printf '%s' "$out" | tr -s ' \n' ' ' | grep -Fq -- "$expect"; then
    ok "$name is refused"
  else
    bad "$name should be refused with: $expect" "$out"
  fi
}

local_server=https://127.0.0.1:26443
default='[orbstack, "kind-*", docker-desktop, minikube]'

echo "guardrails (provider existing):"
case_ orbstack           orbstack "$default"  orbstack "$local_server" "orbstack=$local_server" true ok
case_ orb-local-domain   orbstack "$default"  orbstack https://k8s.orb.local:26443 "orbstack=https://k8s.orb.local:26443" true ok
case_ docker-desktop     docker-desktop "$default" docker-desktop https://kubernetes.docker.internal:6443 "docker-desktop=https://kubernetes.docker.internal:6443" true ok
case_ glob-question-mark kind-a   '["kind-?"]' kind-a   "$local_server" "kind-a=$local_server" true ok
case_ no-confirmation    orbstack "$default"  orbstack "$local_server" "orbstack=$local_server" false "CONFIRM_EXISTING=yes"
case_ context-not-allowed prod-aks "$default" prod-aks "$local_server" "prod-aks=$local_server" true "does not match spec.cluster.existing.allowedContexts"
case_ glob-is-anchored   kind-a-prod '["kind-?"]' kind-a-prod "$local_server" "kind-a-prod=$local_server" true "does not match spec.cluster.existing.allowedContexts"
case_ remote-endpoint    prod-aks '["prod-*"]' prod-aks https://prod-aks-dns.hcp.example.com:443 "prod-aks=https://prod-aks-dns.hcp.example.com:443" true "never installs onto remote clusters"
case_ private-ip         orbstack "$default"  orbstack https://10.1.2.3:6443 "orbstack=https://10.1.2.3:6443" true "never installs onto remote clusters"
case_ contract-mismatch  orbstack "$default"  kind-dev "$local_server" "kind-dev=$local_server" true "but the parameter file names"
case_ snapshot-retargeted orbstack "$default" orbstack "$local_server" "orbstack=https://10.1.2.3:6443" true "never installs onto remote clusters"
case_ extra-context      orbstack "$default"  orbstack "$local_server" "orbstack=$local_server prod-aks=https://prod-aks-dns.hcp.example.com:443" true "must hold only context"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
