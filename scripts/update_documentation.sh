#!/usr/bin/env bash
set -euo pipefail

echo "Diff since last run ($DIFF_FILE):"
cat "$DIFF_FILE"
