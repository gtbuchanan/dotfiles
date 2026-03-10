#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

HTTP_SERVERS=(
  "microsoft-learn https://learn.microsoft.com/api/mcp"
)

for entry in "${HTTP_SERVERS[@]}"; do
  name="${entry%% *}"
  url="${entry#* }"
  claude mcp remove "$name" -s user 2>/dev/null || true
  claude mcp add -s user -t http "$name" "$url"
done
