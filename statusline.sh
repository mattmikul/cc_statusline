#!/usr/bin/env bash
# Claude Code status line script
# Displays: current directory | context window usage | quota usage

input=$(cat)

# Current working directory
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
home="$HOME"
tilde="~"
display_dir="${cwd/#$home/$tilde}"

# Model
model=$(echo "$input" | jq -r '.model.display_name // "?"')

# Context window usage
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
ctx_window=$(echo "$input" | jq -r '.context_window.context_window_size // 0')
ctx_window_k=$(awk -v w="$ctx_window" 'BEGIN { printf "%dk", w/1000 }')

if [ -n "$used_pct" ]; then
  used_int=$(printf "%.0f" "$used_pct")
else
  used_int="0"
fi

# Quota usage via undocumented OAuth endpoint
# Token is read from macOS keychain; results cached for 60s to avoid hammering the API
cache_file="/tmp/cc_quota_cache"
quota_5h="--"; quota_7d="--"

now=$(date +%s)
if [ -f "$cache_file" ]; then
  cache_age=$(( now - $(stat -f %m "$cache_file" 2>/dev/null || echo 0) ))
else
  cache_age=9999
fi

if [ "$cache_age" -gt 60 ]; then
  token=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['claudeAiOauth']['accessToken'])" 2>/dev/null)
  if [ -n "$token" ]; then
    response=$(curl -sf --max-time 3 \
      -H "Authorization: Bearer $token" \
      -H "anthropic-beta: oauth-2025-04-20" \
      "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
    if [ -n "$response" ]; then
      echo "$response" > "$cache_file"
    fi
  fi
fi

if [ -f "$cache_file" ]; then
  quota_5h=$(jq -r '.five_hour.utilization // empty' "$cache_file" 2>/dev/null)
  quota_7d=$(jq -r '.seven_day.utilization // empty' "$cache_file" 2>/dev/null)
  [ -n "$quota_5h" ] && quota_5h="$(printf "%.0f" "$quota_5h")%"
  [ -n "$quota_7d" ] && quota_7d="$(printf "%.0f" "$quota_7d")%"
fi

printf "%s  model:%s  context:%s%%/%s  quota: %s of 5h, %s of 7d" "$display_dir" "$model" "$used_int" "$ctx_window_k" "$quota_5h" "$quota_7d"
