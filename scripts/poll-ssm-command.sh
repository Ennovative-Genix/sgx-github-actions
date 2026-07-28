#!/bin/bash
# Poll SSM command status until completion
# Usage: ./poll-ssm-command.sh <command_id> <instance_id> <region> <step_name> [max_attempts] [poll_interval]

set -e

COMMAND_ID="$1"
INSTANCE_ID="$2"
REGION="$3"
STEP_NAME="$4"
MAX_ATTEMPTS="${5:-60}"
POLL_INTERVAL="${6:-10}"

if [ -z "$COMMAND_ID" ] || [ -z "$INSTANCE_ID" ] || [ -z "$REGION" ] || [ -z "$STEP_NAME" ]; then
  echo "Usage: $0 <command_id> <instance_id> <region> <step_name> [max_attempts] [poll_interval]"
  exit 1
fi

echo "SSM Command ID: $COMMAND_ID"
echo "Polling for command status (Step: $STEP_NAME)..."

ATTEMPT=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
  ATTEMPT=$((ATTEMPT + 1))
  
  STATUS=$(aws ssm get-command-invocation \
    --command-id "$COMMAND_ID" \
    --instance-id "$INSTANCE_ID" \
    --region "$REGION" \
    --query 'Status' \
    --output text 2>/dev/null || echo "Pending")
  
  echo "Attempt $ATTEMPT/$MAX_ATTEMPTS - Status: $STATUS"
  
  case $STATUS in
    Success)
      echo "✓ $STEP_NAME completed successfully"
      exit 0
      ;;
    Failed|Cancelled|TimedOut)
      echo "✗ $STEP_NAME failed with status: $STATUS"
      echo "--- Standard Error Output ---"
      aws ssm get-command-invocation \
        --command-id "$COMMAND_ID" \
        --instance-id "$INSTANCE_ID" \
        --region "$REGION" \
        --query 'StandardErrorContent' \
        --output text 2>/dev/null || echo "(no error output available)"
      echo "--- Standard Output ---"
      aws ssm get-command-invocation \
        --command-id "$COMMAND_ID" \
        --instance-id "$INSTANCE_ID" \
        --region "$REGION" \
        --query 'StandardOutputContent' \
        --output text 2>/dev/null || echo "(no output available)"
      exit 1
      ;;
    InProgress|Pending|Delayed)
      sleep $POLL_INTERVAL
      ;;
    *)
      echo "Unknown status: $STATUS, waiting..."
      sleep $POLL_INTERVAL
      ;;
  esac
done

echo "✗ $STEP_NAME timed out after $MAX_ATTEMPTS attempts ($((MAX_ATTEMPTS * POLL_INTERVAL)) seconds)"
exit 1