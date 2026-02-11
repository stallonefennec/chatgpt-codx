#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${ROOT_DIR}/.local/bin"
TARGET_FILE="${TARGET_DIR}/chatgpt-codx-demo"

log() {
  printf '[install] %s\n' "$*"
}

install_binary() {
  mkdir -p "${TARGET_DIR}"
  cat > "${TARGET_FILE}" <<'BIN'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "--version" ]]; then
  echo "chatgpt-codx-demo 1.0.0"
else
  echo "chatgpt-codx demo binary"
fi
BIN
  chmod +x "${TARGET_FILE}"
  log "Installed demo binary to ${TARGET_FILE}"
}

run_checks() {
  log "Running post-install checks"

  if [[ ! -x "${TARGET_FILE}" ]]; then
    log "Check failed: binary is missing or not executable"
    return 1
  fi

  local version_output
  version_output="$("${TARGET_FILE}" --version)"
  if [[ "${version_output}" != "chatgpt-codx-demo 1.0.0" ]]; then
    log "Check failed: unexpected version output: ${version_output}"
    return 1
  fi

  local default_output
  default_output="$("${TARGET_FILE}")"
  if [[ "${default_output}" != "chatgpt-codx demo binary" ]]; then
    log "Check failed: unexpected default output: ${default_output}"
    return 1
  fi

  log "All checks passed"
}

main() {
  install_binary
  run_checks
  log "Install completed successfully"
}

main "$@"
