#!/usr/bin/env bash
# kubeconform with golden-k8's pinned schema sources (strict mode).
#
#   scripts/kubeconform.sh [kubeconform flags] [files...]   (stdin without files)
#
# Schemas are pinned to commits so results don't drift, and cached in
# build/kubeconform-cache:
#   Kubernetes: yannh/kubernetes-json-schema
#   CRDs (Gateway API, Envoy Gateway, Prometheus Operator, ...): datreeio/CRDs-catalog
# KUBERNETES_VERSION defaults to the cloud default cluster version.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
version="${KUBERNETES_VERSION:-$(yq -r '.spec.cluster.version' "$ROOT/schema/defaults/_cloud.yaml").0}"
cache="$ROOT/build/kubeconform-cache"
mkdir -p "$cache"

exec kubeconform -strict -summary -cache "$cache" -kubernetes-version "$version" \
  -schema-location "https://raw.githubusercontent.com/yannh/kubernetes-json-schema/c416d7b0da0751bd8ebe5be4fa4c8e8274e3bbe2/{{.NormalizedKubernetesVersion}}-standalone{{.StrictSuffix}}/{{.ResourceKind}}{{.KindSuffix}}.json" \
  -schema-location "https://raw.githubusercontent.com/datreeio/CRDs-catalog/c86448cbf1a840ca62d119259864863897c8748a/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json" \
  "$@"
