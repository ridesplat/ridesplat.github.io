#!/bin/bash
# Rasterize Table II from the vector paper at a practical Retina density.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PDF="${1:-}"
IMAGES="$ROOT/static/images"
TABLE_TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ride-results-table.XXXXXX")"

trap 'rm -rf "$TABLE_TMP_DIR"' EXIT

command -v pdftocairo >/dev/null || { echo "pdftocairo not found" >&2; exit 1; }
command -v cwebp >/dev/null || { echo "cwebp not found" >&2; exit 1; }
[ -n "$PDF" ] && [ -f "$PDF" ] || {
  echo "usage: tools/build-results-table.sh /path/to/ride-splat-paper.pdf" >&2
  exit 1
}

# Page 5 at 450 dpi. The crop contains only the vector table body; its caption
# is semantic HTML on the project page. At 2915 px wide this is about 3x the
# table's maximum CSS width and stays crisp on Retina laptops without excess.
pdftocairo -f 5 -l 5 -r 450 -png -singlefile \
  -x 455 -y 590 -W 2915 -H 530 \
  "$PDF" "$TABLE_TMP_DIR/main-results-table"

cp "$TABLE_TMP_DIR/main-results-table.png" "$IMAGES/main-results-table.png"
cwebp -quiet -lossless -z 9 -metadata none \
  "$TABLE_TMP_DIR/main-results-table.png" \
  -o "$IMAGES/main-results-table.webp"

echo "Wrote 2915x530 PNG and lossless WebP Table II assets."
