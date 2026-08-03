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

# Detect whether Claude Code is pointed at a local proxy (e.g. tiny-llm-proxy)
# rather than Anthropic's API. ANTHROPIC_BASE_URL is inherited from the shell
# env that launched Claude Code, since this script runs as its subprocess.
base_url="${ANTHROPIC_BASE_URL:-}"
is_local=0
if [ -n "$base_url" ] && [[ "$base_url" != *"api.anthropic.com"* ]]; then
  is_local=1
fi

if [ "$is_local" -eq 1 ]; then
  # Anthropic quota is meaningless when talking to a local model - skip the
  # lookup entirely and show where we're actually pointed instead. Claude
  # Code's own model.display_name is just its client-side alias (e.g. "Sonnet
  # 5") and doesn't reflect the real backend model, so ask the proxy directly.
  remote_model=$(curl -sf --max-time 1 "$base_url/health" 2>/dev/null | jq -r '.model // empty' 2>/dev/null)

  if [ -n "$remote_model" ]; then
    printf "%s  \xf0\x9f\x8f\xa0 LOCAL:%s  model:%s  context:%s%%/%s" "$display_dir" "$base_url" "$remote_model" "$used_int" "$ctx_window_k"
  else
    printf "%s  \xf0\x9f\x8f\xa0 LOCAL:%s  context:%s%%/%s" "$display_dir" "$base_url" "$used_int" "$ctx_window_k"
  fi
  exit 0
fi

# Quota usage via undocumented OAuth endpoint
# Token is read from macOS keychain (or ~/.claude/.credentials.json on Linux);
# results cached for 60s to avoid hammering the API
cache_file="/tmp/cc_quota_cache"
quota_5h="--"; quota_7d="--"

now=$(date +%s)
if [ -f "$cache_file" ]; then
  if [ "$(uname)" = "Darwin" ]; then
    file_mtime=$(stat -f %m "$cache_file" 2>/dev/null || echo 0)
  else
    file_mtime=$(stat -c %Y "$cache_file" 2>/dev/null || echo 0)
  fi
  cache_age=$(( now - file_mtime ))
else
  cache_age=9999
fi

if [ "$cache_age" -gt 60 ]; then
  if [ "$(uname)" = "Darwin" ]; then
    token=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null \
      | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['claudeAiOauth']['accessToken'])" 2>/dev/null)
  else
    token=$(python3 -c "import json; print(json.load(open('$HOME/.claude/.credentials.json'))['claudeAiOauth']['accessToken'])" 2>/dev/null)
  fi
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
