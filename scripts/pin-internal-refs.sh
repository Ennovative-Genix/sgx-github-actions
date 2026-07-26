#!/usr/bin/env bash
# Rewrite every internal composite-action reference to a given git ref.
#
# Run this when cutting a new major line, so that workflows published under v2
# call the v2 actions rather than whatever `main` happens to hold:
#
#   scripts/pin-internal-refs.sh v2
#   git commit -am "chore: pin internal action references to v2"
#
# Usage: scripts/pin-internal-refs.sh <ref>

set -euo pipefail

REPO_SLUG="Ennovative-Genix/sgx-github-actions"

target_ref="${1:-}"
if [ -z "$target_ref" ]; then
  echo "Usage: $0 <ref>    e.g. $0 v1" >&2
  exit 1
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

mapfile -t files < <(grep -rl "${REPO_SLUG}/actions/" .github/workflows actions 2>/dev/null || true)

if [ "${#files[@]}" -eq 0 ]; then
  echo "No files reference ${REPO_SLUG}/actions/; nothing to do."
  exit 0
fi

for file in "${files[@]}"; do
  # Only the ref after the final @ changes; the action path stays put.
  sed -i -E "s#(${REPO_SLUG}/actions/[A-Za-z0-9._-]+)@[A-Za-z0-9._/-]+#\1@${target_ref}#g" "$file"
  echo "Pinned $file"
done

echo ""
echo "Rewrote ${#files[@]} file(s) to @${target_ref}."
echo "Verify with: scripts/check-internal-refs.sh"
