#!/bin/zsh
# Launch the patched Cursor copy so its Agent talks to a local
# OpenAI-compatible gateway.
#
#   launch-cursor-local.command              set env for this launch only
#   launch-cursor-local.command --persist    also keep env for later launches
#   launch-cursor-local.command --forget     remove the persisted env
#
# Override via env: CURSOR_LOCAL_APP, CURSOR_LOCAL_DATA_DIR,
# GATEWAY_BASE_URL, GATEWAY_API_KEY, CURSOR_LOCAL_PLIST_DIR.
set -euo pipefail

APP="${CURSOR_LOCAL_APP:-$HOME/Applications/CursorLocal.app}"
DATA="${CURSOR_LOCAL_DATA_DIR:-$HOME/Library/Application Support/CursorLocal}"
GATEWAY="${GATEWAY_BASE_URL:-http://127.0.0.1:3425/v1}"
KEY="${GATEWAY_API_KEY:-local}"
PLIST_DIR="${CURSOR_LOCAL_PLIST_DIR:-$HOME/Library/LaunchAgents}"
LABEL="local.cursor-local.env"
PLIST="$PLIST_DIR/$LABEL.plist"
BUNDLE="$APP/Contents/Resources/app/out/vs/workbench/workbench.desktop.main.js"

usage() {
  cat <<'EOF'
Usage: launch-cursor-local.command [--persist | --forget] [--no-check]

  --persist   write a LaunchAgent that re-exports the gateway variables at
              login, so Dock launches work without this script
  --forget    unload and delete that LaunchAgent, then unset the variables
  --no-check  skip the gateway reachability probe

The persisted key lives in plain text in ~/Library/LaunchAgents. Use a local
placeholder key, never a key for a hosted provider.
EOF
}

mode="transient"
check=1
for arg in "$@"; do
  case "$arg" in
    --persist) mode="persist" ;;
    --forget) mode="forget" ;;
    --no-check) check=0 ;;
    -h|--help) usage; exit 0 ;;
    *) print -u2 "unknown argument: $arg"; usage; exit 2 ;;
  esac
done

unset_env() {
  launchctl unsetenv CURSOR_LOCAL_AGENT_BASE_URL 2>/dev/null || true
  launchctl unsetenv CURSOR_LOCAL_AGENT_API_KEY 2>/dev/null || true
}

forget() {
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null ||
    launchctl unload "$PLIST" 2>/dev/null ||
    true
  rm -f "$PLIST"
  unset_env
  echo "persisted env removed"
}

xml_escape() {
  print -r -- "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

persist() {
  mkdir -p "$PLIST_DIR"
  cat >"$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/sh</string>
    <string>-c</string>
    <string>/bin/launchctl setenv CURSOR_LOCAL_AGENT_BASE_URL "\$GATEWAY_BASE_URL"; /bin/launchctl setenv CURSOR_LOCAL_AGENT_API_KEY "\$GATEWAY_API_KEY"</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>GATEWAY_BASE_URL</key>
    <string>$(xml_escape "$GATEWAY")</string>
    <key>GATEWAY_API_KEY</key>
    <string>$(xml_escape "$KEY")</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
EOF
  chmod 600 "$PLIST"
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST"
}

if [[ "$mode" == "forget" ]]; then
  forget
  exit 0
fi

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

if [[ "$check" -eq 1 ]] && ! curl -fsS -m 3 "$GATEWAY/models" >/dev/null 2>&1; then
  echo "gateway not reachable: $GATEWAY/models"
  echo "start the gateway first, or set GATEWAY_BASE_URL (--no-check skips this)"
  exit 1
fi

mkdir -p "$DATA"

launchctl setenv CURSOR_LOCAL_AGENT_BASE_URL "$GATEWAY"
launchctl setenv CURSOR_LOCAL_AGENT_API_KEY "$KEY"

if [[ "$mode" == "persist" ]]; then
  persist
else
  trap unset_env EXIT
fi

open -na "$APP" --args --disable-updates \
  --user-data-dir="$DATA" \
  --extensions-dir="$DATA/extensions"

sleep 3
echo "launched $APP"
if [[ "$mode" == "persist" ]]; then
  echo "env persisted for future launches ($PLIST); undo with --forget"
fi
