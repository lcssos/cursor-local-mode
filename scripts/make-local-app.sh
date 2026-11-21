#!/bin/zsh
# Create a patched copy of Cursor.app whose Agent can use a local
# OpenAI-compatible gateway. The source install is never modified.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: make-local-app.sh [source-app] [dest-app]

  source-app  Cursor.app to copy        (default: /Applications/Cursor.app)
  dest-app    patched copy to create    (default: ~/Applications/CursorLocal.app)

Every bundle file that carries the localMode flag is patched, product.json
checksums are refreshed, and the copy is ad-hoc re-signed. Launch it with
--disable-updates or an update replaces the patch.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

SRC="${1:-/Applications/Cursor.app}"
DEST="${2:-$HOME/Applications/CursorLocal.app}"
APP_REL="Contents/Resources/app"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Files that reference the compile-time flag. The Agents Window (glass) and
# the extension host run their own copies, so patching only the desktop
# workbench leaves parts of the product on the cloud path.
TARGET_FILES=(
  out/main.js
  out/vs/workbench/workbench.desktop.main.js
  out/vs/workbench/workbench.glass.main.js
  out/vs/workbench/api/node/extensionHostProcess.js
  out/vs/code/electron-utility/alwaysLocalSingleton/alwaysLocalSingletonMain.js
)

FLAG_OFF='localMode:!1'
FLAG_ON='localMode:!0'

[[ -d "$SRC" ]] || { print -u2 "source app not found: $SRC"; exit 1; }
[[ -f "$SRC/$APP_REL/out/vs/workbench/workbench.desktop.main.js" ]] || {
  print -u2 "not a Cursor app (missing workbench bundle): $SRC"
  exit 1
}
[[ -e "$DEST" ]] && {
  print -u2 "destination already exists: $DEST"
  print -u2 "remove it (rm -rf \"$DEST\") or pass a different destination"
  exit 1
}

partial="$DEST.partial"
rm -rf "$partial"
mkdir -p "${DEST:h}"

print "==> copying $SRC -> $DEST"
ditto "$SRC" "$partial"

# grep exits 1 when nothing matches; keep that from tripping pipefail.
count_matches() {
  local hits
  hits=$(grep -o "$1" "$2" 2>/dev/null || true)
  if [[ -z "$hits" ]]; then
    print -r -- 0
  else
    print -r -- "$hits" | wc -l | tr -d ' '
  fi
}

print "==> patching localMode"
patched=()
enabled=0
for rel in "${TARGET_FILES[@]}"; do
  file="$partial/$APP_REL/$rel"
  if [[ ! -f "$file" ]]; then
    print "  $rel: not in this build, skipped"
    continue
  fi
  off=$(count_matches "$FLAG_OFF" "$file")
  on=$(count_matches "$FLAG_ON" "$file")
  if [[ "$off" -eq 0 && "$on" -ge 1 ]]; then
    print "  $rel: already enabled"
    enabled=$((enabled + 1))
    continue
  fi
  if [[ "$off" -ne 1 ]]; then
    print -u2 "  $rel: expected exactly one '$FLAG_OFF', found $off"
    print -u2 "  this build may use a different form; inspect with:"
    print -u2 "    grep -abo 'localMode' \"$file\""
    rm -rf "$partial"
    exit 1
  fi
  perl -pi -e 's/localMode:!1/localMode:!0/' "$file"
  grep -q "$FLAG_ON" "$file" || {
    print -u2 "  $rel: patch verification failed"
    rm -rf "$partial"
    exit 1
  }
  print "  $rel: patched"
  patched+=("$rel")
done

if [[ ${#patched[@]} -eq 0 && "$enabled" -eq 0 ]]; then
  print -u2 "no file in this build carries the localMode flag"
  rm -rf "$partial"
  exit 1
fi

if [[ ${#patched[@]} -gt 0 ]]; then
  print "==> refreshing product.json checksums"
  "$SCRIPT_DIR/update-checksums.py" "$partial/$APP_REL" "${patched[@]}"
fi

print "==> ad-hoc signing (this takes a moment)"
codesign --force --deep --sign - "$partial" >/dev/null
codesign --verify --deep --strict "$partial"

mv "$partial" "$DEST"
print "==> done: $DEST"
print "    launch with scripts/launch-cursor-local.command (keep updates disabled)"
