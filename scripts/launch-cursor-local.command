#!/bin/zsh
# Launch the patched Cursor copy so its Agent talks to a local
# OpenAI-compatible gateway. Adjust the defaults below or override via env:
#   CURSOR_LOCAL_APP, CURSOR_LOCAL_DATA_DIR, GATEWAY_BASE_URL, GATEWAY_API_KEY
set -euo pipefail

APP="${CURSOR_LOCAL_APP:-$HOME/Applications/CursorLocal.app}"
DATA="${CURSOR_LOCAL_DATA_DIR:-$HOME/Library/Application Support/CursorLocal}"
GATEWAY="${GATEWAY_BASE_URL:-http://127.0.0.1:3425/v1}"
KEY="${GATEWAY_API_KEY:-local}"
BUNDLE="$APP/Contents/Resources/app/out/vs/workbench/workbench.desktop.main.js"

[[ -d "$APP" ]] || {
  echo "not found: $APP"
  echo "build it first: scripts/make-local-app.sh"
  exit 1
}

grep -q 'localMode:!0' "$BUNDLE" || {
  echo "localMode patch missing in $APP"
  echo "an update probably overwrote it; rebuild with scripts/make-local-app.sh"
  exit 1
}

if ! curl -fsS -m 3 "$GATEWAY/models" >/dev/null 2>&1; then
  echo "gateway not reachable: $GATEWAY/models"
  echo "start the gateway first, or set GATEWAY_BASE_URL"
  exit 1
fi

mkdir -p "$DATA"

cleanup() {
  launchctl unsetenv CURSOR_LOCAL_AGENT_BASE_URL 2>/dev/null || true
  launchctl unsetenv CURSOR_LOCAL_AGENT_API_KEY 2>/dev/null || true
}
trap cleanup EXIT

launchctl setenv CURSOR_LOCAL_AGENT_BASE_URL "$GATEWAY"
launchctl setenv CURSOR_LOCAL_AGENT_API_KEY "$KEY"

open -na "$APP" --args --disable-updates \
  --user-data-dir="$DATA" \
  --extensions-dir="$DATA/extensions"

sleep 3
echo "launched $APP"
