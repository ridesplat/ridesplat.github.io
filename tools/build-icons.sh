#!/bin/bash
# Rebuild raster favicon/touch-icon fallbacks from the canonical SVG mark.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGES="$ROOT/static/images"
SOURCE="$IMAGES/ride-splat-mark.svg"

command -v rsvg-convert >/dev/null || { echo "rsvg-convert not found" >&2; exit 1; }
command -v ffmpeg >/dev/null || { echo "ffmpeg not found" >&2; exit 1; }

rsvg-convert -w 180 -h 180 "$SOURCE" -o "$IMAGES/apple-touch-icon.png"
rsvg-convert -w 32 -h 32 "$SOURCE" -o "$IMAGES/favicon-32.png"
rsvg-convert -w 16 -h 16 "$SOURCE" -o "$IMAGES/favicon-16.png"
ffmpeg -nostdin -y -v error -i "$IMAGES/favicon-32.png" \
  -frames:v 1 "$IMAGES/favicon.ico"

echo "Rebuilt favicon and touch-icon assets."
