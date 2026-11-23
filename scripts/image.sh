#!/usr/bin/env bash
# shellcheck disable=SC2016  # backticks in printf formats are Markdown
# Build the sample app image and load it into the local kind cluster.
#
#   scripts/image.sh [build/config.json] [--confirm-existing]
#
# - Tags the image as spec.app.image and fails if it is 20 MB or more.
# - Makes it available to the cluster in build/contract.json. Nothing is ever
#   pushed to a registry:
#     local                    kind load into the golden-k8 kind cluster
#     existing, kind-<name>    kind load into that kind cluster (--confirm-existing)
#     existing, orbstack or    nothing to load: the cluster shares Docker's
#       docker-desktop         image store (--confirm-existing)
# - Writes build/image.json ({image, id}). The render step stamps the id on
#   the pod template, so a rebuilt image rolls the Deployment and an
#   unchanged one changes nothing.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
config="${1:-$BUILD/config.json}"
confirm="${2:-}"
max_mb=20

fail() { printf 'image: %s\n' "$*" >&2; exit 1; }
info() { printf 'image: %s\n' "$*" >&2; }

[ -f "$config" ] || fail "no config at $config (run: make config ENV=...)"
[ -f "$BUILD/contract.json" ] || fail "no build/contract.json (run: make infra-up ENV=...)"

provider="$(yq -r '.spec.provider' "$config")"
context="$(yq -r '.kube_context' "$BUILD/contract.json")"
case "$provider" in
  local) kind_cluster="$(yq -r '.cluster_name' "$BUILD/contract.json")" target="kind \`$kind_cluster\`" ;;
  existing)
    [ "$confirm" = --confirm-existing ] \
      || fail "$context is a cluster golden-k8 did not create: re-run with CONFIRM_EXISTING=yes (make) or --confirm-existing"
    case "$context" in
      kind-*) kind_cluster="${context#kind-}" target="kind \`$kind_cluster\`" ;;
      orbstack | docker-desktop) kind_cluster="" target="\`$context\` (shares Docker's image store)" ;;
      *) fail "no way to hand a local image to context $context: build it with docker and load it into that cluster yourself" ;;
    esac
    ;;
  *) fail "images are only built for clusters on this machine (got provider $provider); golden-k8 never pushes to a registry" ;;
esac
if [ "$(yq -r '.spec.app.enabled' "$config")" != true ]; then
  info "spec.app.enabled is false: nothing to build"
  exit 0
fi

image="$(yq -r '.spec.app.image' "$config")"
version="$(git -C "$ROOT" describe --tags --always --dirty 2>/dev/null || echo dev)"
revision="$(git -C "$ROOT" rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"

info "building $image ($version)"
# No provenance attestation: it embeds per-build metadata, so every build would
# get a new digest and roll the Deployment. The image never leaves this machine.
docker build --quiet --provenance=false \
  --build-arg "VERSION=$version" --build-arg "REVISION=$revision" \
  -t "$image" "$ROOT/app" >/dev/null

id="$(docker image inspect -f '{{.Id}}' "$image")"
# Uncompressed size = sum of the layers. `docker image inspect .Size` can't be
# used: the containerd image store counts packed + unpacked content.
size="$(docker history --human=false --format '{{.Size}}' "$image" | awk '{ s += $1 } END { print s }')"
size_mb="$(awk -v b="$size" 'BEGIN { printf "%.1f", b / 1000000 }')"
awk -v b="$size" -v max="$max_mb" 'BEGIN { exit !(b < max * 1000000) }' \
  || fail "$image is $size_mb MB, over the $max_mb MB budget"
info "ok  $image is $size_mb MB (< $max_mb MB)"

if [ -n "$kind_cluster" ]; then
  info "loading into kind cluster $kind_cluster"
  kind load docker-image "$image" --name "$kind_cluster" >/dev/null
else
  info "$context shares Docker's image store: nothing to load"
fi

printf '{"image": "%s", "id": "%s"}\n' "$image" "$id" > "$BUILD/image.json"
mkdir -p "$BUILD/summary"
printf '### App image\n\n| Image | Version | Size | Available to |\n|---|---|---|---|\n| `%s` | `%s` | %s MB (budget %s MB) | %s (never pushed) |\n' \
  "$image" "$version" "$size_mb" "$max_mb" "$target" > "$BUILD/summary/image.md"
info "$image ($id) → build/image.json"
