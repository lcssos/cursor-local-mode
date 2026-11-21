#!/bin/zsh
# Create a patched copy of Cursor.app whose Agent can use a local
# OpenAI-compatible gateway. The source install is never modified.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: make-local-app.sh [source-app] [dest-app]

  source-app  Cursor.app to copy        (default: /Applications/Cursor.app)
  dest-app    patched copy to create    (default: ~/Applications/CursorLocal.app)

The copy is ad-hoc re-signed; launch it with --disable-updates or an update
replaces the patch.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

SRC="${1:-/Applications/Cursor.app}"
DEST="${2:-$HOME/Applications/CursorLocal.app}"
BUNDLE_REL="Contents/Resources/app/out/vs/workbench/workbench.desktop.main.js"

[[ -d "$SRC" ]] || { print -u2 "source app not found: $SRC"; exit 1; }
[[ -f "$SRC/$BUNDLE_REL" ]] || {
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

BUNDLE="$partial/$BUNDLE_REL"

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

before=$(count_matches 'localMode:!1' "$BUNDLE")
after=$(count_matches 'localMode:!0' "$BUNDLE")

if [[ "$before" -eq 0 && "$after" -ge 1 ]]; then
  print "==> bundle already enables localMode, skipping patch"
elif [[ "$before" -ne 1 ]]; then
  print -u2 "expected exactly one 'localMode:!1', found $before"
  print -u2 "this build may use a different form; inspect with:"
  print -u2 "  grep -abo 'localMode' \"$BUNDLE\""
  rm -rf "$partial"
  exit 1
else
  print "==> patching localMode:!1 -> localMode:!0"
  perl -pi -e 's/localMode:!1/localMode:!0/' "$BUNDLE"
  grep -q 'localMode:!0' "$BUNDLE" || {
    print -u2 "patch verification failed"
    rm -rf "$partial"
    exit 1
  }
fi

print "==> ad-hoc signing (this takes a moment)"
codesign --force --deep --sign - "$partial" >/dev/null
codesign --verify --deep --strict "$partial"

mv "$partial" "$DEST"
print "==> done: $DEST"
print "    launch with scripts/launch-cursor-local.command (keep updates disabled)"
