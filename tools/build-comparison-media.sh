#!/bin/bash
# Build the packed comparison videos and dataset tours.
# Source masters live outside the website repository; only static/videos changes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_MEDIA="${RIDE_SPLAT_MEDIA_ROOT:-$ROOT/../.video}"
COMPARISON_MASTERS="$SOURCE_MEDIA/raw-comparisons/v1-shared-path"
DATASET_MASTERS="$SOURCE_MEDIA/raw-dataset/side-by-side"
OUTPUT="$ROOT/static/videos"

AV1_CRF=32
H264_CRF=23
PHONE_WIDTH=1280
TABLET_WIDTH=1920
RESPONSIVE_AV1_CRF=37
RESPONSIVE_H264_CRF=25

command -v ffmpeg >/dev/null || { echo "ffmpeg not found" >&2; exit 1; }
command -v ffprobe >/dev/null || { echo "ffprobe not found" >&2; exit 1; }

video_signature() {
  ffprobe -v error -select_streams v:0 -count_frames \
    -show_entries stream=width,height,r_frame_rate,nb_read_frames \
    -of csv=p=0 "$1"
}

require_matching_sources() {
  local expected
  local file
  expected="$(video_signature "$1")"
  shift
  for file in "$@"; do
    if [ "$(video_signature "$file")" != "$expected" ]; then
      echo "source mismatch: $file" >&2
      echo "expected: $expected" >&2
      echo "actual:   $(video_signature "$file")" >&2
      exit 1
    fi
  done
}

pack_comparison() {
  local scene="$1"
  local three_dgs="$2"
  local dcgaussian="$3"
  local robustsplat="$4"
  local ours="$5"
  local base="$OUTPUT/compare_${scene}_4way"
  local filter
  local h264_filter
  local h264_output='[out]'

  require_matching_sources "$three_dgs" "$dcgaussian" "$robustsplat" "$ours"

  filter='[0:v]setpts=PTS-STARTPTS[tl];[1:v]setpts=PTS-STARTPTS[tr];[2:v]setpts=PTS-STARTPTS[bl];[3:v]setpts=PTS-STARTPTS[br];[tl][tr]hstack=inputs=2:shortest=1[top];[bl][br]hstack=inputs=2:shortest=1[bottom];[top][bottom]vstack=inputs=2:shortest=1[out]'
  h264_filter="$filter"

  # Town02's full 3840x2560 pack exceeds the widely hardware-decoded H.264 4K
  # envelope. AV1 retains every source pixel; only the compatibility fallback
  # is proportionally reduced to 3240x2160 (still 1620x1080 per quadrant).
  if [ "$scene" = "xld_Town02" ]; then
    h264_filter="$filter;[out]scale=3240:2160:flags=lanczos[h264out]"
    h264_output='[h264out]'
  fi

  echo "==> $scene: AV1"
  ffmpeg -nostdin -y -v error \
    -i "$three_dgs" -i "$dcgaussian" -i "$robustsplat" -i "$ours" \
    -filter_complex "$filter" -map '[out]' -an \
    -c:v libsvtav1 -preset 6 -crf "$AV1_CRF" -svtav1-params tune=0 \
    -pix_fmt yuv420p -g 120 -tag:v av01 -movflags +faststart \
    -map_metadata -1 "$base.av1.mp4"

  echo "==> $scene: H.264 fallback"
  ffmpeg -nostdin -y -v error \
    -i "$three_dgs" -i "$dcgaussian" -i "$robustsplat" -i "$ours" \
    -filter_complex "$h264_filter" -map "$h264_output" -an \
    -c:v libx264 -preset slow -crf "$H264_CRF" -profile:v high \
    -pix_fmt yuv420p -movflags +faststart -map_metadata -1 "$base.mp4"

  ffmpeg -nostdin -y -v error -ss 0.5 -i "$base.mp4" \
    -vf 'scale=1280:-2:flags=lanczos' -frames:v 1 -q:v 4 \
    "$base"_poster.jpg
}

build_dataset() {
  local scene="$1"
  local source="$DATASET_MASTERS/dataset_${scene}.mp4"
  local base="$OUTPUT/dataset_${scene}"

  echo "==> dataset $scene: AV1"
  ffmpeg -nostdin -y -v error -i "$source" \
    -map 0:v:0 -an \
    -c:v libsvtav1 -preset 6 -crf "$AV1_CRF" -svtav1-params tune=0 \
    -pix_fmt yuv420p -g 20 -tag:v av01 -movflags +faststart \
    -map_metadata -1 "$base.av1.mp4"

  echo "==> dataset $scene: lossless H.264 fast-start remux"
  ffmpeg -nostdin -y -v error -i "$source" \
    -map 0:v:0 -an -c:v copy -movflags +faststart \
    -map_metadata -1 "$base.mp4"

  ffmpeg -nostdin -y -v error -ss 0.5 -i "$base.mp4" \
    -frames:v 1 -q:v 4 "$base"_poster.jpg
}

build_responsive_comparison() {
  local scene="$1"
  local tier="$2"
  local width="$3"
  local base="$OUTPUT/compare_${scene}_4way"

  # The canvas is capped at 2x device pixel ratio. The 1280px phone and 1920px
  # tablet/laptop packs avoid a 3.8K decode and multi-tens-of-megabytes transfer
  # while retaining enough source resolution for interactive quadrant crops.
  # Transcode each codec from its matching high-quality delivery file so this
  # target can also be rebuilt without access to the private source renders.
  echo "==> $scene: $tier AV1"
  ffmpeg -nostdin -y -v error -i "$base.av1.mp4" \
    -map 0:v:0 -an -vf "scale=${width}:-2:flags=lanczos" \
    -c:v libsvtav1 -preset 6 -crf "$RESPONSIVE_AV1_CRF" -svtav1-params tune=0 \
    -pix_fmt yuv420p -g 120 -tag:v av01 -movflags +faststart \
    -map_metadata -1 "$base.$tier.av1.mp4"

  echo "==> $scene: $tier H.264"
  ffmpeg -nostdin -y -v error -i "$base.mp4" \
    -map 0:v:0 -an -vf "scale=${width}:-2:flags=lanczos" \
    -c:v libx264 -preset slow -crf "$RESPONSIVE_H264_CRF" -profile:v high \
    -pix_fmt yuv420p -movflags +faststart \
    -map_metadata -1 "$base.$tier.mp4"
}

build_all_responsive_comparisons() {
  local scene
  for scene in rs2 xld_Town02 wayve_s004 wayve_s005; do
    build_responsive_comparison "$scene" phone "$PHONE_WIDTH"
    build_responsive_comparison "$scene" tablet "$TABLET_WIDTH"
  done
}

mkdir -p "$OUTPUT"

if [ "${1:-}" = "--responsive-only" ]; then
  [ "$#" -eq 1 ] || { echo "usage: $0 [--responsive-only]" >&2; exit 2; }
  build_all_responsive_comparisons
  echo "Done. Run ./cache_bust.py --apply after changing media."
  exit 0
fi

[ "$#" -eq 0 ] || { echo "usage: $0 [--responsive-only]" >&2; exit 2; }

pack_comparison rs2 \
  "$COMPARISON_MASTERS/rs2_3dgs.mp4" \
  "$COMPARISON_MASTERS/rs2_dcgaussian.mp4" \
  "$COMPARISON_MASTERS/rs2_robustsplat.mp4" \
  "$COMPARISON_MASTERS/rs2_ours.mp4"

pack_comparison xld_Town02 \
  "$COMPARISON_MASTERS/xld_Town02_3dgs_frames077-216.mp4" \
  "$COMPARISON_MASTERS/xld_Town02_dcgaussian_frames077-216.mp4" \
  "$COMPARISON_MASTERS/xld_Town02_robustsplat_frames077-216.mp4" \
  "$COMPARISON_MASTERS/xld_Town02_ours_frames077-216.mp4"

pack_comparison wayve_s004 \
  "$COMPARISON_MASTERS/wayve_s004_3dgs.mp4" \
  "$COMPARISON_MASTERS/wayve_s004_dcgaussian.mp4" \
  "$COMPARISON_MASTERS/wayve_s004_robustsplat.mp4" \
  "$COMPARISON_MASTERS/wayve_s004_ours.mp4"

pack_comparison wayve_s005 \
  "$COMPARISON_MASTERS/wayve_s005_3dgs.mp4" \
  "$COMPARISON_MASTERS/wayve_s005_dcgaussian.mp4" \
  "$COMPARISON_MASTERS/wayve_s005_robustsplat.mp4" \
  "$COMPARISON_MASTERS/wayve_s005_ours.mp4"

build_all_responsive_comparisons

build_dataset rs1
build_dataset rs2
build_dataset rs3

echo "Done. Run ./cache_bust.py --apply after changing media."
