#!/usr/bin/env bash
# Verify that every reference this repository makes to its own composite actions
# points at a directory that exists, and that all of them use the same git ref.
#
# Reusable workflows cannot use `uses: ./actions/...` to reach their own
# repository: when a workflow is called from another repository, `./` resolves
# against the *consumer's* checkout. So internal references are written in the
# full `owner/repo/path@ref` form, and that ref has to stay consistent -- a
# workflow tagged v2 that still calls an action at @v1 is a silent regression.
#
# Usage: scripts/check-internal-refs.sh

set -euo pipefail

REPO_SLUG="Ennovative-Genix/sgx-github-actions"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

status=0
declare -a refs_seen=()

echo "Scanning for references to ${REPO_SLUG}/actions/*"

while IFS= read -r line; do
  file="${line%%:*}"
  rest="${line#*:}"

  # Pull `owner/repo/actions/<name>@<ref>` out of the matched line.
  reference="$(printf '%s' "$rest" | grep -oE "${REPO_SLUG}/actions/[A-Za-z0-9._-]+@[A-Za-z0-9._/-]+" | head -n1)"
  [ -n "$reference" ] || continue

  action_path="${reference%@*}"
  action_ref="${reference##*@}"
  action_name="${action_path##*/}"

  if [ ! -f "actions/${action_name}/action.yml" ]; then
    echo "::error file=${file}::References 'actions/${action_name}', which does not exist."
    status=1
  fi

  refs_seen+=("$action_ref")
done < <(grep -rn "${REPO_SLUG}/actions/" .github/workflows actions 2>/dev/null || true)

if [ "${#refs_seen[@]}" -eq 0 ]; then
  echo "::warning::No internal action references found. Expected the workflows to call this repository's composite actions."
  exit "$status"
fi

unique_refs="$(printf '%s\n' "${refs_seen[@]}" | sort -u)"
unique_count="$(printf '%s\n' "$unique_refs" | wc -l | tr -d ' ')"

echo "Found ${#refs_seen[@]} internal reference(s) using ref(s):"
printf '%s\n' "$unique_refs" | sed 's/^/  /'

if [ "$unique_count" -ne 1 ]; then
  echo "::error::Internal action references disagree on the git ref. Run scripts/pin-internal-refs.sh <ref> to make them consistent."
  status=1
fi

# During a release the refs must already match the tag being published,
# otherwise v2 workflows would keep calling v1 actions.
if [ -n "${TAG:-}" ]; then
  expected_major="${TAG%%.*}"
  actual="$(printf '%s' "$unique_refs" | head -n1)"

  if [ "$actual" != "$expected_major" ] && [ "$actual" != "$TAG" ]; then
    echo "::warning::Publishing ${TAG} while internal references point at '${actual}'. Consumers pinned to ${expected_major} will get actions from '${actual}'."
  fi
fi

if [ "$status" -eq 0 ]; then
  echo "All internal references resolve and agree."
fi

exit "$status"
