#!/usr/bin/env bash
# Terraform tests for every module and stack that has a tests/ directory.
# Fixtures (terraform/tests/fixtures/*.yaml) are normalized with
# scripts/config.sh first, so they always satisfy the config contract.
# No cloud credentials or Docker needed: stacks use mock providers.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
fixtures="$ROOT/build/test-fixtures"
mkdir -p "$fixtures"

echo "fixtures:"
for f in terraform/tests/fixtures/*.yaml; do
  scripts/config.sh "$f" "$fixtures/$(basename "${f%.yaml}").json" 2>&1 | sed 's/^/  /'
done

status=0
for dir in terraform/modules/*/ terraform/stacks/*/; do
  [ -d "$dir/tests" ] || continue
  echo
  echo "== ${dir%/}"
  terraform -chdir="$dir" init -backend=false -input=false >/dev/null
  terraform -chdir="$dir" test || status=1
done
exit "$status"
