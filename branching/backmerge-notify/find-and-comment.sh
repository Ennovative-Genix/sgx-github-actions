#!/usr/bin/env bash
# Find conflicted / stale back-merge PRs, comment on them, emit GITHUB_OUTPUT.
# Requires: GH_TOKEN, REPO. Optional: EVENT_NAME, PR_NUMBER, STALE_HOURS, BACKMERGE_LABEL
set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${REPO:?REPO is required}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"

EVENT_NAME="${EVENT_NAME:-schedule}"
PR_NUMBER="${PR_NUMBER:-}"
STALE_HOURS="${STALE_HOURS:-24}"
LABEL="${BACKMERGE_LABEL:-backmerge}"

NEED_ATTENTION=$(mktemp)
trap 'rm -f "$NEED_ATTENTION"' EXIT
: > "$NEED_ATTENTION"

check_pr() {
  local NUM="$1"
  local JSON STATE MERGEABLE TITLE URL BASE CREATED REASON=""
  JSON=$(gh pr view "$NUM" --repo "$REPO" --json number,title,url,baseRefName,headRefName,mergeable,createdAt,updatedAt,state)
  STATE=$(echo "$JSON" | jq -r '.state')
  [ "$STATE" = "OPEN" ] || return 0

  MERGEABLE=$(echo "$JSON" | jq -r '.mergeable')
  TITLE=$(echo "$JSON" | jq -r '.title')
  URL=$(echo "$JSON" | jq -r '.url')
  BASE=$(echo "$JSON" | jq -r '.baseRefName')
  CREATED=$(echo "$JSON" | jq -r '.createdAt')

  if [ "$MERGEABLE" = "CONFLICTING" ]; then
    REASON="CONFLICTING"
  else
    local CREATED_EPOCH NOW_EPOCH AGE_H
    CREATED_EPOCH=$(date -d "$CREATED" +%s)
    NOW_EPOCH=$(date +%s)
    AGE_H=$(( (NOW_EPOCH - CREATED_EPOCH) / 3600 ))
    if [ "$AGE_H" -ge "$STALE_HOURS" ]; then
      REASON="STALE (${AGE_H}h open)"
    fi
  fi

  if [ -n "$REASON" ]; then
    printf '%s\t%s\t%s\t%s\t%s\n' "$NUM" "$REASON" "$TITLE" "$URL" "$BASE" >> "$NEED_ATTENTION"
    gh pr comment "$NUM" --repo "$REPO" \
      --body "Back-merge needs attention: **${REASON}**. Please resolve and merge when green. (shared branching notify)" || true
  fi
}

if [ "$EVENT_NAME" = "pull_request" ] && [ -n "$PR_NUMBER" ]; then
  check_pr "$PR_NUMBER"
else
  while IFS= read -r NUM; do
    [ -z "$NUM" ] && continue
    check_pr "$NUM"
  done < <(gh pr list --repo "$REPO" --state open --label "$LABEL" --limit 50 --json number --jq '.[].number')
fi

COUNT=$(wc -l < "$NEED_ATTENTION" | tr -d ' ')
echo "count=${COUNT}" >> "$GITHUB_OUTPUT"
{
  echo "rows<<EOF"
  cat "$NEED_ATTENTION"
  echo "EOF"
} >> "$GITHUB_OUTPUT"
echo "Found ${COUNT} back-merge PR(s) needing attention"
