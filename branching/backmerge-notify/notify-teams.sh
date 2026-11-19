#!/usr/bin/env bash
# Post a Teams MessageCard for back-merge PRs that need attention.
# Requires: REPO, ROWS. Optional: WEBHOOK (skip notify if empty)
set -euo pipefail

: "${REPO:?REPO is required}"
ROWS="${ROWS:-}"

if [ -z "${WEBHOOK:-}" ]; then
  echo "::warning::TEAMS_WEBHOOK_BRANCHING secret is not set — skipped Teams notify. PR comments were still posted."
  exit 0
fi

if [ -z "$ROWS" ]; then
  echo "No rows to notify"
  exit 0
fi

FACTS=""
while IFS=$'\t' read -r NUM REASON TITLE URL BASE; do
  [ -z "${NUM:-}" ] && continue
  FACTS="${FACTS}{\"name\":\"#${NUM} → ${BASE} (${REASON})\",\"value\":\"[${TITLE}](${URL})\"},"
done <<< "$ROWS"
FACTS="${FACTS%,}"

PAYLOAD=$(cat <<EOF
{
  "@type": "MessageCard",
  "@context": "http://schema.org/extensions",
  "themeColor": "FF8C00",
  "summary": "Back-merge PRs need attention in ${REPO}",
  "title": "Back-merge needs attention — ${REPO}",
  "sections": [{
    "facts": [${FACTS}],
    "text": "Humans: resolve conflicts / merge when green. Bot does not auto-merge."
  }]
}
EOF
)

curl -sS -f -H 'Content-Type: application/json' -d "$PAYLOAD" "$WEBHOOK"
echo "Teams notify sent"
