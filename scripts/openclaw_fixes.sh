#!/usr/bin/env bash
set -euo pipefail

# Shared curl flags for stable non-interactive behavior.
CURL_FLAGS=(--fail --location --silent --show-error)

log() {
  printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

# Download backup content from GitHub with layered fallbacks.
# Usage:
#   restore_from_github \
#     "owner/repo" "tag" "asset-name.tgz" "path/in/repo/backup.tgz" "main" "/tmp/backup.tgz" "${GITHUB_TOKEN:-}"
restore_from_github() {
  local repo="$1"
  local tag="$2"
  local asset_name="$3"
  local raw_path="$4"
  local branch="$5"
  local output_file="$6"
  local token="${7:-}"

  local auth_header=()
  if [[ -n "$token" ]]; then
    auth_header=(-H "Authorization: Bearer ${token}")
  fi

  # 1) Try release asset URL directly.
  local release_url="https://github.com/${repo}/releases/download/${tag}/${asset_name}"
  log "Trying release asset: ${release_url}"
  if curl "${CURL_FLAGS[@]}" "${auth_header[@]}" -o "$output_file" "$release_url"; then
    log "Downloaded release asset to ${output_file}"
    return 0
  fi

  warn "Release asset not found. Trying branch raw file fallback..."

  # 2) Fall back to raw branch file.
  local raw_url="https://raw.githubusercontent.com/${repo}/${branch}/${raw_path}"
  log "Trying raw branch file: ${raw_url}"
  if curl "${CURL_FLAGS[@]}" "${auth_header[@]}" -o "$output_file" "$raw_url"; then
    log "Downloaded raw backup to ${output_file}"
    return 0
  fi

  # 3) Last fallback: GitHub contents API (works with private repos + PAT).
  warn "Raw URL not found. Trying GitHub contents API..."
  local api_url="https://api.github.com/repos/${repo}/contents/${raw_path}?ref=${branch}"

  if command -v jq >/dev/null 2>&1; then
    if curl "${CURL_FLAGS[@]}" "${auth_header[@]}" "$api_url" \
      | jq -er '.content' \
      | tr -d '\n' \
      | base64 -d > "$output_file"; then
      log "Downloaded backup via GitHub API to ${output_file}"
      return 0
    fi
  fi

  warn "All backup download methods failed for repo=${repo}, tag=${tag}, path=${raw_path}."
  return 1
}

# Pause only when attached to an interactive terminal.
pause_if_interactive() {
  local prompt="${1:-Press Enter to continue...}"
  if [[ -t 0 ]]; then
    read -r -p "$prompt"
  else
    log "Non-interactive shell detected; skipping pause"
  fi
}
