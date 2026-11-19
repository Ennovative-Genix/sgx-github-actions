#!/usr/bin/env bash
# Enforce Nova head/base branch naming rules.
# Requires: HEAD_REF, BASE_REF. Optional: PR_URL
set -euo pipefail

: "${HEAD_REF:?HEAD_REF is required}"
: "${BASE_REF:?BASE_REF is required}"

fail() { echo "::error::$1"; exit 1; }

echo "PR ${PR_URL:-unknown}"
echo "head=${HEAD_REF}  base=${BASE_REF}"

case "$HEAD_REF" in
  main) ;;
  development) ;;
  feature/*|fix/*|release/*|hotfix/*|chore/*) ;;
  *)
    fail "Head branch '${HEAD_REF}' is not allowed. Use feature/<ticket>-<desc>, fix/<ticket>-<desc>, release/vX.Y.Z, hotfix/<ticket>-<desc>, or chore/* (automation)."
    ;;
esac

if [ "$BASE_REF" = "main" ]; then
  case "$HEAD_REF" in
    release/*|hotfix/*) ;;
    *)
      fail "PRs into main are only allowed from release/** or hotfix/** (got head '${HEAD_REF}'). Merge the STG-approved release or hotfix — do not open feature/fix PRs into main."
      ;;
  esac
fi

case "$HEAD_REF" in
  feature/*|fix/*|hotfix/*)
    if ! echo "$HEAD_REF" | grep -Eq '^(feature|fix|hotfix)/(ADO-[0-9]+|[0-9]+)-[a-z0-9-]+$'; then
      echo "::warning::Preferred pattern is feature|fix|hotfix/ADO-<id>-<short-desc> (lowercase, hyphens). Head '${HEAD_REF}' still allowed."
    fi
    ;;
  release/*)
    if ! echo "$HEAD_REF" | grep -Eq '^release/v[0-9]+\.[0-9]+\.[0-9]+([._-].+)?$'; then
      echo "::warning::Preferred release pattern is release/vX.Y.Z (got '${HEAD_REF}')."
    fi
    ;;
esac

echo "Branch guards passed"
