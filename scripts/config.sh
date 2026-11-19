#!/usr/bin/env bash
# Normalize an environment file into a validated config.
#
#   scripts/config.sh <environment.yaml> [output.json]
#
# 1. Validate the environment file against schema/golden.schema.json
# 2. Deep-merge defaults: _common → _cloud (aws/gcp/azure) → <provider> → environment
# 3. Validate the result against schema/config.schema.json
# 4. Semantic checks JSON Schema can't express
# Output defaults to build/config.json.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCHEMA_DIR="$ROOT/schema"
DEFAULTS_DIR="$SCHEMA_DIR/defaults"

env_file="${1:?usage: config.sh <environment.yaml> [output.json]}"
out_file="${2:-$ROOT/build/config.json}"

fail() { printf 'config: %s\n' "$*" >&2; exit 1; }

[ -f "$env_file" ] || fail "no such file: $env_file"

# 1. Input schema (errors point at the user's own file)
validate() { # <schema> <instance> <message>: print validator output only on failure
  local out
  out="$(check-jsonschema --color never --schemafile "$1" "$2" 2>&1)" || { printf '%s\n' "$out" >&2; fail "$3"; }
}
validate "$SCHEMA_DIR/golden.schema.json" "$env_file" "$env_file does not match schema/golden.schema.json"

# 2. Layered defaults
provider="$(yq -r '.spec.provider' "$env_file")"
layers=("$DEFAULTS_DIR/_common.yaml")
case "$provider" in
  aws|gcp|azure) layers+=("$DEFAULTS_DIR/_cloud.yaml") ;;
esac
layers+=("$DEFAULTS_DIR/$provider.yaml" "$env_file")

mkdir -p "$(dirname "$out_file")"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
# Maps merge deeply; arrays (e.g. nodePools) are replaced, not appended.
# shellcheck disable=SC2016  # $doc is a yq variable, not a shell one
yq eval-all -o json '. as $doc ireduce ({}; . * $doc) | sort_keys(..)' "${layers[@]}" > "$tmp"

# 3. Normalized schema (every defaulted field present)
validate "$SCHEMA_DIR/config.schema.json" "$tmp" "merged config for $env_file does not match schema/config.schema.json (check schema/defaults/)"

# 4. Semantic checks
errors="$(yq -r '
  [
    (.spec.cluster.nodePools // [] | .[] | select(.min > .max)
      | "spec.cluster.nodePools[" + .name + "]: min (" + (.min|tostring) + ") must be <= max (" + (.max|tostring) + ")"),
    (.spec.cluster.nodePools // [] | group_by(.name) | .[] | select(length > 1)
      | "spec.cluster.nodePools: duplicate pool name \"" + .[0].name + "\"")
  ] | .[]
' "$tmp")"
if [ -n "$errors" ]; then
  printf '%s\n' "$errors" | sed 's/^/  /' >&2
  fail "$env_file failed semantic checks"
fi

mv "$tmp" "$out_file"
trap - EXIT
printf 'config: %s → %s (%s)\n' "$env_file" "${out_file#"$ROOT"/}" "$provider" >&2
