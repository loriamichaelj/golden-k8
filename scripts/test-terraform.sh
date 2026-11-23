#!/usr/bin/env bash
# shellcheck disable=SC2016  # backticks in printf formats are Markdown
# Terraform tests for every module and stack that has a tests/ directory.
# Fixtures (terraform/tests/fixtures/*.yaml) are normalized with
# scripts/config.sh first, so they always satisfy the config contract.
# No cloud credentials or Docker needed: stacks use mock providers.
# Writes a Markdown summary to build/summary/terraform.md.
#
#   scripts/test-terraform.sh             everything
#   scripts/test-terraform.sh <provider>  one provider's stack and modules, plus
#                                         the shared modules and the parity check
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
provider="${1:-}"
case "$provider" in
  "" | local | existing | aws | gcp | azure) ;;
  *) echo "test-terraform: unknown provider '$provider'" >&2; exit 2 ;;
esac
fixtures="$ROOT/build/test-fixtures"
mkdir -p "$fixtures"
# One provider download per version for every module and stack (the AWS
# provider alone is a few hundred MB). Lock file hashes are still verified.
export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-$ROOT/build/terraform-plugins}"
mkdir -p "$TF_PLUGIN_CACHE_DIR"

echo "fixtures:"
for f in terraform/tests/fixtures/*.yaml; do
  scripts/config.sh "$f" "$fixtures/$(basename "${f%.yaml}").json" 2>&1 | sed 's/^/  /'
done
# The shipped cloud examples are fixtures too (env-<name>.json), so they always plan.
for f in environments/*-example.yaml; do
  scripts/config.sh "$f" "$fixtures/env-$(basename "${f%.yaml}").json" 2>&1 | sed 's/^/  /'
done

# Markdown summary for CI job summaries.
mkdir -p "$ROOT/build/summary"
summary="$ROOT/build/summary/terraform.md"
scope="every module and stack"
[ -z "$provider" ] || scope="provider \`$provider\` plus the shared modules"
printf '### Terraform tests\n\nMocked providers: no cloud credentials, no Docker. Scope: %s.\n\n| Module / stack | Passed | Failed | Result |\n|---|---:|---:|---|\n' "$scope" > "$summary"

# Shared modules sit directly under modules/; provider modules under modules/<provider>/.
if [ -z "$provider" ]; then
  dirs=(terraform/modules/*/ terraform/modules/*/*/ terraform/stacks/*/ terraform/tests/parity/)
else
  dirs=(terraform/modules/*/ terraform/modules/"$provider"/*/ terraform/stacks/"$provider"/ terraform/tests/parity/)
fi

status=0
for dir in "${dirs[@]}"; do
  [ -d "$dir/tests" ] || continue
  echo
  echo "== ${dir%/}"
  terraform -chdir="$dir" init -backend=false -input=false >/dev/null
  log="$(mktemp)"
  terraform -chdir="$dir" test | tee "$log" || status=1
  # Last line: "Success! N passed, M failed." / "Failure! N passed, M failed."
  result="$(sed 's/\x1b\[[0-9;]*m//g' "$log" | grep -E '^(Success|Failure)!' | tail -n 1)"
  rm -f "$log"
  passed="$(printf '%s' "$result" | sed -nE 's/.* ([0-9]+) passed.*/\1/p')"
  failed="$(printf '%s' "$result" | sed -nE 's/.* ([0-9]+) failed.*/\1/p')"
  case "$result" in Success*) mark="✅" ;; *) mark="❌" ;; esac
  printf '| `%s` | %s | %s | %s |\n' "${dir%/}" "${passed:-?}" "${failed:-?}" "$mark" >> "$summary"
done
exit "$status"
