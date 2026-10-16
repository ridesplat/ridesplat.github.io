#!/bin/bash
#
# Rebuild the web-delivery media from the high-quality originals.
#
# The originals in static/videos/*.mp4 and static/images/*.png are kept as the
# masters and are never modified. This script regenerates the derived files the
# page actually serves:
#
#   <name>.mp4        (master, untouched)
#   <name>.web.mp4    H.264 for delivery - universal support
#   <name>.web.webm   VP9 for delivery   - ~30% smaller where supported
#   <name>_poster.jpg first frame, so a <video> paints something before it loads
#
# Delivery copies are capped at 1280px wide. The widest column these sit in is
# 1152 CSS px, so a 1600px source spends bandwidth on pixels that are scaled
# back down before anyone sees them. 1280 still covers a retina phone at full
# width and was indistinguishable from the source in side-by-side stills.
#
# Usage: tools/build-media.sh [name ...]     (default: everything referenced)
#
# Packed comparison and vertically stacked dataset files are built from the
# preserved media/ masters by tools/build-comparison-media.sh and are excluded
# here so a generic rebuild cannot transcode a delivery file as though it were
# an original.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VIDEOS="$ROOT/static/videos"
IMAGES="$ROOT/static/images"
MAX_WIDTH=1280

command -v ffmpeg >/dev/null || { echo "ffmpeg not found (brew install ffmpeg)" >&2; exit 1; }

# A master is any .mp4 that is not itself a generated delivery copy.
collect_masters() {
  find "$VIDEOS" -maxdepth 1 -name "*.mp4" \
    ! -name "*.web.mp4" ! -name "*.av1.mp4" \
    ! -name "*_compressed.mp4" ! -name "*_4way.mp4" \
    ! -name "dataset_rs*.mp4" | sort
}

if [ $# -gt 0 ]; then
  MASTERS=()
  for name in "$@"; do
    MASTERS+=("$VIDEOS/${name%.mp4}.mp4")
  done
else
  MASTERS=()
  while IFS= read -r line; do MASTERS+=("$line"); done < <(collect_masters)
fi

mkdir -p "$IMAGES"

for src in "${MASTERS[@]}"; do
  [ -f "$src" ] || { echo "skip (no such master): $src" >&2; continue; }
  base="$(basename "$src" .mp4)"

  width=$(ffprobe -v error -select_streams v:0 -show_entries stream=width \
            -of default=nw=1:nk=1 "$src")
  # Downscale only; never upscale a source that is already small.
  if [ "$width" -gt "$MAX_WIDTH" ]; then
    scale="scale=${MAX_WIDTH}:-2:flags=lanczos"
  else
    scale="scale=trunc(iw/2)*2:trunc(ih/2)*2"
  fi

  echo "==> $base (${width}px source)"

  # -an: every one of these clips is silent, and an empty audio track still
  # costs a stream header plus a decoder the browser has to set up.
  # +faststart: moves the moov atom to the front so playback can begin before
  # the whole file has arrived.
  ffmpeg -nostdin -y -v error -i "$src" \
    -vf "$scale" \
    -c:v libx264 -crf 22 -preset slow -profile:v high -pix_fmt yuv420p \
    -movflags +faststart -an \
    "$VIDEOS/$base.web.mp4"

  ffmpeg -nostdin -y -v error -i "$src" \
    -vf "$scale" \
    -c:v libvpx-vp9 -crf 33 -b:v 0 -row-mt 1 -deadline good -cpu-used 2 \
    -pix_fmt yuv420p -an \
    "$VIDEOS/$base.web.webm"

  # Poster frame. Seeking a little way in avoids the fade-ins some clips open
  # with, which would otherwise give a near-black still.
  ffmpeg -nostdin -y -v error -ss 0.5 -i "$src" \
    -vf "$scale" -frames:v 1 -q:v 4 \
    "$IMAGES/${base}_poster.jpg"

  m=$(( $(stat -f%z "$VIDEOS/$base.web.mp4") / 1024 ))
  w=$(( $(stat -f%z "$VIDEOS/$base.web.webm") / 1024 ))
  o=$(( $(stat -f%z "$src") / 1024 ))
  printf "    master %6s KB  ->  mp4 %6s KB   webm %6s KB\n" "$o" "$m" "$w"
done

echo
echo "Done. Run ./cache_bust.py --apply so the new files are picked up."
