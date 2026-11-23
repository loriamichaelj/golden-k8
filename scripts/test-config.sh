#!/usr/bin/env bash
# Config contract tests.
#   - tests/schema/valid/*.yaml, environments/*.yaml and examples/*/environments/*.yaml
#     must normalize cleanly
#   - tests/schema/invalid/*.yaml must fail, and the error output must contain
#     the text on the file's first line: "# expect: <substring>"
#   - CI=true forces observability profile lite (with a warning)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

pass=0; fail=0
ok()  { pass=$((pass + 1)); printf '  \033[32mok\033[0m    %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  \033[31mFAIL\033[0m  %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/        /'; }

echo "valid:"
for f in tests/schema/valid/*.yaml environments/*.yaml examples/*/environments/*.yaml; do
  [ -e "$f" ] || continue
  if out="$(scripts/config.sh "$f" "$tmp/out.json" 2>&1)"; then ok "$f"; else bad "$f" "$out"; fi
done

echo "invalid:"
for f in tests/schema/invalid/*.yaml; do
  expect="$(sed -n '1s/^# expect: //p' "$f")"
  if [ -z "$expect" ]; then bad "$f" "missing '# expect: …' on line 1"; continue; fi
  if out="$(scripts/config.sh "$f" "$tmp/out.json" 2>&1)"; then
    bad "$f" "expected failure, but it passed"
  elif printf '%s' "$out" | grep -Fq -- "$expect"; then
    ok "$f"
  else
    bad "$f" "failed, but not with: $expect"$'\n'"$out"
  fi
done

echo "ci override:"
f=tests/schema/valid/standard-profile.yaml
if out="$(env -u CI -u GITHUB_ACTIONS scripts/config.sh "$f" "$tmp/out.json" 2>&1)" \
  && [ "$(yq -r '.spec.observability.profile' "$tmp/out.json")" = standard ]; then
  ok "$f keeps profile standard outside CI"
else
  bad "$f keeps profile standard outside CI" "$out"
fi
if out="$(env -u GITHUB_ACTIONS CI=true scripts/config.sh "$f" "$tmp/out.json" 2>&1)" \
  && [ "$(yq -r '.spec.observability.profile' "$tmp/out.json")" = lite ] \
  && printf '%s' "$out" | grep -Fq "is ignored in CI: using lite"; then
  ok "$f is forced to lite in CI, with a warning"
else
  bad "$f is forced to lite in CI, with a warning" "$out"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
