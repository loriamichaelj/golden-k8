#!/usr/bin/env bash
# Release helpers. A release is a commit on main whose golden-path workflow
# defaults golden-ref to its own tag, so `@vX.Y.Z` and `@vX` callers run the
# Terraform, Ansible and manifests of the same release.
#
#   scripts/release.sh prepare X.Y.Z   set golden-ref's default to vX.Y.Z and add
#                                      a CHANGELOG section (commit it in a PR)
#   scripts/release.sh check vX.Y.Z    verify a tag is releasable (used by
#                                      .github/workflows/release.yml)
#
# After the prepare PR is merged: git tag vX.Y.Z <merge commit> && git push
# origin vX.Y.Z. The release workflow publishes the release and moves vX.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
workflow=.github/workflows/golden-path.yml

fail() { printf 'release: %s\n' "$*" >&2; exit 1; }
info() { printf 'release: %s\n' "$*" >&2; }

semver='^[0-9]+\.[0-9]+\.[0-9]+$'

# The default of the golden-ref input in the reusable workflow.
current_default() {
  yq -r '.on.workflow_call.inputs.golden-ref.default' "$workflow"
}

case "${1:-}" in
  prepare)
    version="${2:-}"
    [[ "$version" =~ $semver ]] || fail "usage: scripts/release.sh prepare X.Y.Z (got '${version}')"
    tag="v$version"
    git rev-parse -q --verify "refs/tags/$tag" >/dev/null && fail "tag $tag already exists"

    # Edit the one line in place (yq would reformat the file).
    line="$(awk '/^      golden-ref:$/ { inside = 1 } inside && /^        default:/ { print NR; exit }' "$workflow")"
    [ -n "$line" ] || fail "golden-ref default not found in $workflow"
    sed -i.bak "${line}s/default: .*/default: $tag/" "$workflow" && rm -f "$workflow.bak"
    [ "$(current_default)" = "$tag" ] || fail "could not set golden-ref's default to $tag"
    info "$workflow: golden-ref defaults to $tag"

    if ! grep -q "^## $tag " CHANGELOG.md; then
      today="$(date -u +%Y-%m-%d)"
      awk -v head="## $tag ($today)" '
        !done && /^## / { print head "\n\n- Describe the changes in this release.\n"; done = 1 }
        { print }
        END { if (!done) print "\n" head "\n\n- Describe the changes in this release." }
      ' CHANGELOG.md > CHANGELOG.md.new && mv CHANGELOG.md.new CHANGELOG.md
      info "CHANGELOG.md: added a $tag section; describe the release there"
    fi
    info "next: commit in a PR; after merging, tag the merge commit $tag and push the tag"
    ;;

  check)
    tag="${2:-}"
    [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "tag must look like vX.Y.Z (got '$tag')"
    [ "$(current_default)" = "$tag" ] \
      || fail "$workflow defaults golden-ref to $(current_default), not $tag: run scripts/release.sh prepare ${tag#v} first"
    grep -q "^## $tag " CHANGELOG.md || fail "CHANGELOG.md has no '## $tag' section"
    info "ok  $tag: golden-ref default and CHANGELOG match"
    ;;

  *)
    fail "usage: scripts/release.sh prepare X.Y.Z | check vX.Y.Z"
    ;;
esac
