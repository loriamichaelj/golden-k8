#!/usr/bin/env bash
# shellcheck disable=SC2016  # backticks in printf formats are Markdown
# Misconfiguration scans of the infrastructure and app manifests.
#
#   scripts/security-scan.sh
#
# Trivy gates: any HIGH or CRITICAL finding fails the scan (accepted findings,
# each with a reason, are in .trivyignore). Checkov reports only: without its
# paid API its findings carry no severity, so they inform rather than gate.
# Both write SARIF for GitHub code scanning to build/security/, and a Markdown
# summary goes to build/summary/security.md.
#
# Scope: terraform/modules (every provider's network and cluster settings,
# including the registry modules they wrap) and k8s/app. The stacks only feed
# the parameter file into those modules; scanners can't evaluate values that
# come from a file at runtime, so scanning the stacks gives false positives.
#
# Nothing is sent to the scanners' vendors: telemetry and version checks are
# off. Trivy still downloads its public check bundle into build/trivy-cache.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
out="$ROOT/build/security"
rm -rf "$out"
mkdir -p "$out" "$ROOT/build/summary"

targets=(terraform/modules k8s/app)

trivy_args=(config --disable-telemetry --skip-version-check --quiet
  --cache-dir "$ROOT/build/trivy-cache" --skip-dirs '**/.terraform' --ignorefile "$ROOT/.trivyignore")

# Checkov: no guideline lookups or downloads from its vendor.
export BC_SKIP_MAPPING=TRUE CHECKOV_RUN_SCA_PACKAGE_SCAN_V2=false

status=0
rows=""
for target in "${targets[@]}"; do
  name="$(basename "$target")"

  # Trivy: SARIF with every severity for the Security tab, then the gate.
  trivy "${trivy_args[@]}" --format sarif --output "$out/trivy-$name.sarif" "$target"
  if ! trivy "${trivy_args[@]}" --severity HIGH,CRITICAL --exit-code 1 "$target"; then
    status=1
  fi

  # Checkov, report only.
  case "$target" in
    terraform/*) framework=terraform ;;
    *) framework=kubernetes ;;
  esac
  checkov --directory "$target" --framework "$framework" --quiet --compact --soft-fail \
    --skip-download --skip-path '\.terraform' \
    --output cli --output sarif --output-file-path "console,$out/checkov-$name.sarif" >/dev/null

  # Code scanning needs repository-relative paths: Trivy writes them relative
  # to the target, Checkov repeats the target. Registry module paths
  # (terraform-aws-modules/...) aren't in the repository and stay as they are.
  for sarif in "$out/trivy-$name.sarif" "$out/checkov-$name.sarif"; do
    T="$target" yq -i -p json -o json '
      (.runs[].results[].locations[].physicalLocation.artifactLocation.uri) |= (
        sub("^" + strenv(T) + "/" + strenv(T) + "/"; strenv(T) + "/")
        | (if test("^(terraform|k8s)/|^terraform-aws-modules/") then . else strenv(T) + "/" + . end)
      )' "$sarif"
  done

  count() { # <sarif> <level...> → number of results at those levels
    local file="$1"; shift
    local levels; levels="$(printf '"%s",' "$@")"
    yq -p json -o yaml ".runs[].results[] | select(.level as \$l | [${levels%,}] | contains([\$l]))" "$file" 2>/dev/null \
      | grep -c '^ruleId:' || true
  }
  t_high="$(count "$out/trivy-$name.sarif" error)"
  t_other="$(count "$out/trivy-$name.sarif" warning note)"
  c_all="$(count "$out/checkov-$name.sarif" error warning note)"
  mark="✅"; [ "$t_high" -eq 0 ] || mark="❌"
  rows+="| \`$target\` | $mark $t_high | $t_other | $c_all |"$'\n'
done

{
  printf '### Security scan\n\n'
  printf 'Trivy gates on HIGH/CRITICAL (accepted findings with reasons in `.trivyignore`). Checkov reports only. Full results: Security tab (code scanning).\n\n'
  printf '| Target | Trivy high/critical | Trivy medium/low | Checkov failed checks |\n|---|---:|---:|---:|\n'
  printf '%s' "$rows"
} > "$ROOT/build/summary/security.md"

cat "$ROOT/build/summary/security.md"
exit "$status"
