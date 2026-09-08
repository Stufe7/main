#!/bin/sh
# Local workspace only: copy brand masters from Docs/ into the frontend static root.
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Docs/icons and logos"
DST="$ROOT/frontend/static"
cp "$SRC/stufe7-logo.svg" "$SRC/stufe7-logo-dark.svg" "$SRC/stufe7-mark.svg" \
  "$SRC/stufe7-mark-plain.svg" "$SRC/favicon.svg" "$SRC/favicon.ico" \
  "$SRC/apple-touch-icon.png" "$SRC/icon-192.png" "$SRC/icon-512.png" \
  "$SRC/site.webmanifest" "$DST/"
echo "published brand assets to $DST"
