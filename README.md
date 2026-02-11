# chatgpt-codx

This repository now includes a small shell utility module that addresses two failure modes reported in OpenClaw-like maintenance scripts:

1. **GitHub backup restore 404 loop** when release assets and raw fallback URLs do not exist.
2. **Blocking `Press Enter to continue...` prompt** in non-interactive runs (e.g., CI or automation).

## Added helper script

- `scripts/openclaw_fixes.sh`

### What it provides

- `restore_from_github`: tries multiple download strategies in order:
  1. GitHub release asset URL.
  2. Raw file from a branch.
  3. GitHub Contents API (with optional PAT, and `jq` when available).
- `pause_if_interactive`: only pauses if stdin is an interactive TTY.

## Example integration

```bash
source ./scripts/openclaw_fixes.sh

restore_from_github \
  "owner/repo" \
  "v1.2.3" \
  "backup.tar.gz" \
  "backups/backup.tar.gz" \
  "main" \
  "/tmp/backup.tar.gz" \
  "${GITHUB_PAT:-}"

# Replace hardcoded blocking pause:
pause_if_interactive "Press Enter to continue..."
```

## Validation

```bash
bash -n scripts/openclaw_fixes.sh
```
