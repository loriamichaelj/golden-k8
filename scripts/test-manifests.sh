#!/usr/bin/env bash
# Manifest tests: build every app overlay with Kustomize and validate the
# output with kubeconform (strict, Kubernetes + CRD schemas).
#
#   scripts/test-manifests.sh
#
# Schema sources are pinned to commits so results don't drift:
#   Kubernetes: yannh/kubernetes-json-schema
#   CRDs (HTTPRoute, ServiceMonitor, ...): datreeio/CRDs-catalog
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

K8S_VERSION="$(yq -r '.spec.cluster.version' schema/defaults/_cloud.yaml).0"
K8S_SCHEMAS="https://raw.githubusercontent.com/yannh/kubernetes-json-schema/c416d7b0da0751bd8ebe5be4fa4c8e8274e3bbe2/{{.NormalizedKubernetesVersion}}-standalone{{.StrictSuffix}}/{{.ResourceKind}}{{.KindSuffix}}.json"
CRD_SCHEMAS="https://raw.githubusercontent.com/datreeio/CRDs-catalog/c86448cbf1a840ca62d119259864863897c8748a/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"

pass=0; fail=0
for overlay in k8s/app/overlays/*/; do
  overlay="${overlay%/}"
  if out="$(kubectl kustomize "$overlay" 2>&1 \
      | kubeconform -strict -summary -kubernetes-version "$K8S_VERSION" \
          -schema-location "$K8S_SCHEMAS" -schema-location "$CRD_SCHEMAS" 2>&1)"; then
    pass=$((pass + 1)); printf '  \033[32mok\033[0m    %s  %s\n' "$overlay" "$(printf '%s' "$out" | tail -n 1)"
  else
    fail=$((fail + 1)); printf '  \033[31mFAIL\033[0m  %s\n' "$overlay"; printf '%s\n' "$out" | sed 's/^/        /'
  fi
done

printf '\n%d passed, %d failed (Kubernetes %s)\n' "$pass" "$fail" "$K8S_VERSION"
[ "$fail" -eq 0 ]
