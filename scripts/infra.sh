#!/usr/bin/env bash
# Create or destroy the infrastructure for a normalized config.
#
#   scripts/infra.sh up|down [build/config.json]
#
# Picks terraform/stacks/<provider>, keeps one state file per environment in
# build/state/, and writes the outputs contract to build/contract.json.
# Refuses to apply unless spec.pipeline.apply is true (only possible for
# local/existing; golden-k8 never provisions cloud resources).
#
# provider existing creates nothing and never contacts the cluster: "up" copies
# only spec.cluster.existing.context out of $KUBECONFIG (default
# ~/.kube/config) into build/kubeconfig-golden-<name>, and the stack refuses
# contexts that are not allowed or not local. "down" only forgets that state;
# use make down to remove what golden-k8 installed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"

action="${1:?usage: infra.sh up|down [config.json]}"
config="${2:-$BUILD/config.json}"

fail() { printf 'infra: %s\n' "$*" >&2; exit 1; }
info() { printf 'infra: %s\n' "$*" >&2; }

[ -f "$config" ] || fail "no config at $config (run: make config ENV=...)"
config="$(cd "$(dirname "$config")" && pwd)/$(basename "$config")"

provider="$(yq -r '.spec.provider' "$config")"
name="$(yq -r '.metadata.name' "$config")"
apply="$(yq -r '.spec.pipeline.apply' "$config")"
stack="$ROOT/terraform/stacks/$provider"
state="$BUILD/state/$provider-$name.tfstate"

if [ "$action" = "up" ] && [ "$apply" != "true" ]; then
  fail "spec.pipeline.apply is false for $provider/$name: refusing to apply (golden-k8 never provisions cloud resources)"
fi
[ -d "$stack" ] || fail "no stack for provider '$provider' yet (terraform/stacks/$provider)"

if [ "$provider" = "local" ]; then
  docker info >/dev/null 2>&1 || fail "Docker engine not reachable. Start OrbStack/Docker and retry."
fi

if [ "$provider" = "existing" ] && [ "$action" = "up" ]; then
  context="$(yq -r '.spec.cluster.existing.context' "$config")"
  source_kubeconfig="${KUBECONFIG:-$HOME/.kube/config}"
  snapshot="$BUILD/kubeconfig-golden-$name"
  mkdir -p "$BUILD"
  # --minify keeps only this context; --flatten inlines its credentials.
  ( umask 077
    kubectl config view --kubeconfig "$source_kubeconfig" --minify --flatten --context "$context" > "$snapshot.tmp" ) \
    || { rm -f "$snapshot.tmp"; fail "context '$context' not found in $source_kubeconfig"; }
  mv "$snapshot.tmp" "$snapshot"
  info "existing: snapshot of context $context → ${snapshot#"$ROOT"/} (no cluster contacted)"
fi

tf() { terraform -chdir="$stack" "$@"; }
mkdir -p "$BUILD/state"
tf init -input=false -reconfigure -backend-config="path=$state" >/dev/null

vars=(-var "config_path=$config" -var "build_dir=$BUILD")

case "$action" in
  up)
    info "applying $provider/$name (state: ${state#"$ROOT"/})"
    if ! tf apply -input=false -auto-approve "${vars[@]}"; then
      # Never leave credentials of a refused context behind.
      if [ "$provider" = "existing" ]; then rm -f "$snapshot"; fi
      fail "terraform apply failed for $provider/$name"
    fi
    tf output -json contract > "$BUILD/contract.json"
    info "contract → build/contract.json"
    kubeconfig="$(yq -r '.kubeconfig_path' "$BUILD/contract.json")"
    context="$(yq -r '.kube_context' "$BUILD/contract.json")"
    if [ "$provider" = "local" ]; then
      # The provider only waits for the control plane; wait for every node.
      kubectl --kubeconfig "$kubeconfig" --context "$context" wait node --all --for=condition=Ready --timeout=180s >/dev/null
      kubectl --kubeconfig "$kubeconfig" --context "$context" get nodes -L golden-k8/pool
    fi
    info "kubectl: export KUBECONFIG=${kubeconfig#"$ROOT"/}"
    ;;
  down)
    if [ ! -f "$state" ]; then info "nothing to destroy for $provider/$name"; exit 0; fi
    kubeconfig="$(tf output -json contract 2>/dev/null | yq -p json -o yaml '.kubeconfig_path // ""' || true)"
    info "destroying $provider/$name"
    tf destroy -input=false -auto-approve "${vars[@]}"
    rm -f "$BUILD/contract.json" "$state" "$state.backup"
    if [ -n "$kubeconfig" ]; then rm -f "$kubeconfig"; fi
    ;;
  *)
    fail "unknown action '$action' (expected up or down)"
    ;;
esac
