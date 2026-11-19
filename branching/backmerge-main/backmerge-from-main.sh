#!/usr/bin/env bash
# Open / refresh back-merge PRs: main → development, and main → each open release/*
# Never auto-merges. Requires: GH_TOKEN, REPO, SHA
set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${REPO:?REPO is required}"
: "${SHA:?SHA is required}"

SHORT_SHA="${SHA:0:7}"
LABEL="${BACKMERGE_LABEL:-backmerge}"

gh label create "$LABEL" --repo "$REPO" --color BFD4F2 \
  --description "Automated back-merge from main" 2>/dev/null || true

BODY_FILE=$(mktemp)
trap 'rm -f "$BODY_FILE"' EXIT

cat > "$BODY_FILE" <<EOF
## Automated back-merge

\`main\` moved (\`${SHORT_SHA}\`). This PR brings those commits into the target branch.

**Do not squash-merge.** Prefer a merge commit so history stays clear.

### Checklist
- [ ] Conflicts resolved (if any)
- [ ] Checks green
- [ ] Merge when ready — bot will not auto-merge

---
_Opened/updated by shared branching action. Label: \`${LABEL}\`._
EOF

ensure_pr() {
  local BASE="$1"
  local TITLE="$2"

  if ! gh api "repos/${REPO}/branches/${BASE}" --jq '.name' >/dev/null 2>&1; then
    echo "Skip: base branch '${BASE}' does not exist"
    return 0
  fi

  local AHEAD
  AHEAD=$(gh api "repos/${REPO}/compare/${BASE}...main" --jq '.ahead_by')
  if [ "${AHEAD}" = "0" ]; then
    echo "Skip: '${BASE}' already contains main"
    local EXISTING
    EXISTING=$(gh pr list --repo "$REPO" --base "$BASE" --head main --state open --json number --jq '.[0].number // empty')
    if [ -n "$EXISTING" ]; then
      gh pr close "$EXISTING" --repo "$REPO" --comment "Closing: \`${BASE}\` already contains \`main\`."
    fi
    return 0
  fi

  local EXISTING
  EXISTING=$(gh pr list --repo "$REPO" --base "$BASE" --head main --state open --json number --jq '.[0].number // empty')
  if [ -n "$EXISTING" ]; then
    echo "Updating existing PR #${EXISTING} → ${BASE} (${AHEAD} commit(s) ahead)"
    gh pr edit "$EXISTING" --repo "$REPO" --title "$TITLE" --body-file "$BODY_FILE"
    gh pr edit "$EXISTING" --repo "$REPO" --add-label "$LABEL" 2>/dev/null || true
    gh pr comment "$EXISTING" --repo "$REPO" --body "Refreshed after \`main\` @ \`${SHORT_SHA}\` (\`${AHEAD}\` commit(s) still ahead)."
  else
    echo "Creating PR main → ${BASE} (${AHEAD} commit(s) ahead)"
    gh pr create --repo "$REPO" --base "$BASE" --head main \
      --title "$TITLE" \
      --body-file "$BODY_FILE" \
      --label "$LABEL"
  fi
}

ensure_pr "development" "chore: back-merge main into development"

while IFS= read -r REL; do
  [ -z "$REL" ] && continue
  ensure_pr "$REL" "chore: back-merge main into ${REL} (hotfix sync)"
done < <(gh api "repos/${REPO}/branches" --paginate --jq '.[].name' | grep -E '^release/' || true)

echo "Back-merge pass complete"
