#!/usr/bin/env bash
# Send shell commands to an EC2 instance over SSM and wait for the result.
#
# Every value arrives through the environment rather than through workflow
# interpolation, so nothing in the payload can break out into the runner shell.

set -euo pipefail

: "${SSM_INSTANCE_ID:?instance-id is required}"
: "${SSM_REGION:?region is required}"
: "${SSM_COMMANDS:?commands are required}"
: "${SSM_STEP_NAME:?step-name is required}"

max_attempts="${SSM_MAX_ATTEMPTS:-60}"
poll_interval="${SSM_POLL_INTERVAL:-10}"
continue_on_error="${SSM_CONTINUE_ON_ERROR:-false}"
working_directory="${SSM_WORKING_DIRECTORY:-}"

params_file="$(mktemp)"
trap 'rm -f "$params_file"' EXIT

# `commands` arrives as a newline separated block but SSM wants a JSON array of
# strings. jq keeps the quoting correct no matter what the payload contains,
# which is what the hand-rolled string concatenation used to get wrong.
jq -n \
  --arg commands "$SSM_COMMANDS" \
  --arg workdir "$working_directory" \
  '{
     commands: ($commands | rtrimstr("\n") | split("\n") | map(select(length > 0))),
     workingDirectory: (if ($workdir | length) > 0 then [$workdir] else [] end)
   }
   | with_entries(select(.value | length > 0))' > "$params_file"

echo "::group::SSM payload :: ${SSM_STEP_NAME}"
cat "$params_file"
echo "::endgroup::"

command_id="$(aws ssm send-command \
  --instance-ids "$SSM_INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --comment "${SSM_STEP_NAME:0:100}" \
  --parameters "file://$params_file" \
  --region "$SSM_REGION" \
  --query 'Command.CommandId' \
  --output text)"

echo "command-id=$command_id" >> "$GITHUB_OUTPUT"
echo "SSM command id: $command_id"

invocation_field() {
  aws ssm get-command-invocation \
    --command-id "$command_id" \
    --instance-id "$SSM_INSTANCE_ID" \
    --region "$SSM_REGION" \
    --query "$1" \
    --output text 2>/dev/null || echo ""
}

attempt=0
status="Pending"

while [ "$attempt" -lt "$max_attempts" ]; do
  attempt=$((attempt + 1))

  # The invocation is not queryable for a moment after send-command returns, so
  # a lookup failure early on means "not registered yet", not "broken".
  status="$(invocation_field 'Status')"
  [ -n "$status" ] || status="Pending"

  echo "attempt ${attempt}/${max_attempts} - status: ${status}"

  case "$status" in
    Success)
      break
      ;;
    Failed | Cancelled | TimedOut)
      break
      ;;
    *)
      sleep "$poll_interval"
      ;;
  esac
done

echo "status=$status" >> "$GITHUB_OUTPUT"

echo "::group::SSM stdout :: ${SSM_STEP_NAME}"
invocation_field 'StandardOutputContent'
echo "::endgroup::"

if [ "$status" = "Success" ]; then
  echo "${SSM_STEP_NAME} completed successfully."
  exit 0
fi

echo "::group::SSM stderr :: ${SSM_STEP_NAME}"
invocation_field 'StandardErrorContent'
echo "::endgroup::"

if [ "$status" = "Pending" ] || [ "$status" = "InProgress" ] || [ "$status" = "Delayed" ]; then
  message="${SSM_STEP_NAME} timed out after ${max_attempts} attempts ($((max_attempts * poll_interval))s)."
else
  message="${SSM_STEP_NAME} finished with status ${status}."
fi

{
  echo "### SSM step failed: ${SSM_STEP_NAME}"
  echo ""
  echo "- Instance: \`${SSM_INSTANCE_ID}\`"
  echo "- Region: \`${SSM_REGION}\`"
  echo "- Command id: \`${command_id}\`"
  echo "- Status: \`${status}\`"
} >> "$GITHUB_STEP_SUMMARY"

if [ "$continue_on_error" = "true" ]; then
  echo "::warning title=SSM step failed::${message} Continuing because continue-on-error is set."
  exit 0
fi

echo "::error title=SSM step failed::${message}"
exit 1
