#!/usr/bin/env bash
# shellcheck disable=SC2016  # backticks in printf formats are Markdown
# Render everything golden-k8 would apply for an environment, without a
# cluster, and validate it with kubeconform. Works for every provider.
#
#   scripts/render.sh [build/config.json]
#
# Contract: build/contract.json when it belongs to this environment (after
# make infra-up); otherwise a placeholder (build/render/contract.json) with the
# provider's gateway shape and no real endpoints.
# Output: build/rendered/{platform,values,releases,app.yaml} and a Markdown
# summary in build/summary/render.md.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
config="${1:-$BUILD/config.json}"

fail() { printf 'render: %s\n' "$*" >&2; exit 1; }
info() { printf 'render: %s\n' "$*" >&2; }

[ -f "$config" ] || fail "no config at $config (run: make config ENV=...)"
[ "$config" -ef "$BUILD/config.json" ] || cp "$config" "$BUILD/config.json"

provider="$(yq -r '.spec.provider' "$BUILD/config.json")"
name="$(yq -r '.metadata.name' "$BUILD/config.json")"
profile="$(yq -r '.spec.observability.profile' "$BUILD/config.json")"
cluster="golden-$name"

mkdir -p "$BUILD/render"
contract="$BUILD/contract.json"
if [ -f "$contract" ] && [ "$(yq -r '.provider' "$contract")" = "$provider" ] \
    && [ "$(yq -r '.cluster_name' "$contract")" = "$cluster" ]; then
  contract_kind="outputs of the $provider stack (build/contract.json)"
else
  contract="$BUILD/render/contract.json"
  contract_kind="placeholder: no cluster, $provider gateway shape"
  if [ "$provider" = local ]; then gw_type=NodePort gw_port=30080; else gw_type=LoadBalancer gw_port=null; fi
  cat > "$contract" <<JSON
{
  "contract_version": "v1",
  "provider": "$provider",
  "cluster_name": "$cluster",
  "cluster_endpoint": "https://cluster.invalid",
  "kubeconfig_path": "/dev/null",
  "kube_context": "$cluster",
  "storage_class": "standard",
  "gateway_service_type": "$gw_type",
  "gateway_node_port": $gw_port,
  "lb_annotations": {},
  "network_id": null,
  "private_subnet_ids": []
}
JSON
fi
info "$provider/$name (profile $profile), contract: $contract_kind"

rm -rf "$BUILD/rendered"
GOLDEN_CONTRACT="$contract" "$ROOT/scripts/playbook.sh" render >"$BUILD/render/playbook.log" 2>&1 \
  || { cat "$BUILD/render/playbook.log" >&2; fail "render playbook failed (log: build/render/playbook.log)"; }

# Validate every rendered file and count what it contains.
mkdir -p "$BUILD/summary"
summary="$BUILD/summary/render.md"
{
  printf '### Rendered manifests: %s/%s\n\n' "$provider" "$name"
  printf 'Profile `%s`. Contract: %s. Schemas: kubeconform, strict.\n\n' "$profile" "$contract_kind"
  printf '| File | Resources | Kinds | Schema check |\n|---|---:|---|---|\n'
} > "$summary"

failed=0 total=0
cd "$BUILD/rendered"
for file in platform/*.yaml app.yaml releases/*.yaml; do
  [ -f "$file" ] || continue
  count="$(yq ea -N 'select(.kind != null) | .kind' "$file" | wc -l | tr -d ' ')"
  kinds="$(yq ea -N 'select(.kind != null) | .kind' "$file" | sort | uniq -c | sort -rn \
    | awk '{ printf "%s%s×%s", (NR > 1 ? ", " : ""), $2, $1 }')"
  total=$((total + count))
  if out="$("$ROOT/scripts/kubeconform.sh" "$file" 2>&1)"; then
    check="✅ valid"
    printf '  \033[32mok\033[0m    %-36s %4s resources\n' "$file" "$count"
  else
    failed=$((failed + 1)); check="❌ invalid"
    printf '  \033[31mFAIL\033[0m  %-36s %4s resources\n' "$file" "$count"
    printf '%s\n' "$out" | grep -v '^Summary' | sed 's/^/        /'
  fi
  printf '| `%s` | %s | %s | %s |\n' "$file" "$count" "$kinds" "$check" >> "$summary"
done
printf '| **Total** | **%s** | | |\n' "$total" >> "$summary"

[ "$failed" -eq 0 ] || fail "$failed rendered file(s) failed schema validation"
info "ok  $total resources rendered and valid → build/rendered/ (summary: build/summary/render.md)"
