#!/usr/bin/env bash
# Manifest tests: build every app overlay with Kustomize and validate the
# output with kubeconform (strict, Kubernetes + CRD schemas).
#
#   scripts/test-manifests.sh
#
# Schemas: see scripts/kubeconform.sh (pinned, strict).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

pass=0; fail=0
for overlay in k8s/app/overlays/*/; do
  overlay="${overlay%/}"
  if out="$(kubectl kustomize "$overlay" 2>&1 \
      | scripts/kubeconform.sh 2>&1)"; then
    pass=$((pass + 1)); printf '  \033[32mok\033[0m    %s  %s\n' "$overlay" "$(printf '%s' "$out" | tail -n 1)"
  else
    fail=$((fail + 1)); printf '  \033[31mFAIL\033[0m  %s\n' "$overlay"; printf '%s\n' "$out" | sed 's/^/        /'
  fi
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
