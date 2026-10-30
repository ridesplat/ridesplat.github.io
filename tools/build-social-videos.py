#!/usr/bin/env python3
"""Build RIDE-Splat social comparison and dataset montage videos.

The comparison exports reproduce the moving-wipe format used by
tuallen.github.io/media/ridesplat_rs2.mp4: one selected baseline quadrant is
revealed against the bottom-right RIDE-Splat quadrant with a white sinusoidal
divider and method labels. The dataset montage labels each row by scene.
Exports default to 1080px-wide H.264 delivery files so upload services do not
have to discard the full-resolution comparison pixels.

Outputs are written to ./social by default. That directory is intentionally
gitignored because these are upload artifacts rather than website assets.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import tempfile
from dataclasses import dataclass
from fractions import Fraction
from pathlib import Path
from typing import Optional, Sequence

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
VIDEO_DIR = ROOT / "static" / "videos"


@dataclass(frozen=True)
class WipeSpec:
    slug: str
    source: str
    baseline: str
    column: int
    row: int


WIPES: Sequence[WipeSpec] = (
    WipeSpec(
        slug="town02_dcgaussian",
        source="compare_xld_Town02_4way.av1.mp4",
        baseline="DC-Gaussian",
        column=1,
        row=0,
    ),
    WipeSpec(
        slug="scene_004_robustsplat",
        source="compare_wayve_s004_4way.av1.mp4",
        baseline="RobustSplat",
        column=0,
        row=1,
    ),
    WipeSpec(
        slug="scene_005_3dgs",
        source="compare_wayve_s005_4way.av1.mp4",
        baseline="3DGS",
        column=0,
        row=0,
    ),
)

DATASET_ROWS = (
    ("dataset_rs1.mp4", "Leesburg"),
    ("dataset_rs2.mp4", "Martin"),
    ("dataset_rs3.mp4", "Reston"),
)


def require_tool(name: str) -> str:
    path = shutil.which(name)
    if not path:
        raise SystemExit(f"Required tool not found: {name}")
    return path


def probe(ffprobe: str, source: Path) -> dict:
    result = subprocess.run(
        [
            ffprobe,
            "-v",
            "error",
            "-select_streams",
            "v:0",
            "-show_entries",
            "stream=width,height,r_frame_rate,nb_frames:format=duration",
            "-of",
            "json",
            str(source),
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    payload = json.loads(result.stdout)
    stream = payload["streams"][0]
    return {
        "width": int(stream["width"]),
        "height": int(stream["height"]),
        "fps": Fraction(stream["r_frame_rate"]),
        "frames": int(stream["nb_frames"]),
        "duration": float(payload["format"]["duration"]),
    }


def find_font(bold: bool) -> Path:
    environment_name = "RIDE_SPLAT_SOCIAL_FONT_BOLD" if bold else "RIDE_SPLAT_SOCIAL_FONT"
    configured = os.environ.get(environment_name)
    candidates = [
        Path(configured) if configured else None,
        Path("/System/Library/Fonts/Supplemental/Arial Bold.ttf") if bold else None,
        Path("/System/Library/Fonts/Supplemental/Arial.ttf") if not bold else None,
        Path("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf") if bold else None,
        Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf") if not bold else None,
    ]
    for candidate in candidates:
        if candidate and candidate.is_file():
            return candidate
    raise SystemExit(
        f"No suitable {'bold ' if bold else ''}font found; set {environment_name}."
    )


def make_label(
    output: Path,
    title: str,
    subtitle: Optional[str],
    width: int,
    compact: bool = False,
) -> None:
    scale = max(0.55, min(1.15, width / 1900))
    title_size = round((48 if compact else 62) * scale)
    subtitle_size = round(46 * scale)
    padding_x = round((22 if compact else 28) * scale)
    padding_y = round((14 if compact else 20) * scale)
    gap = round(6 * scale)
    title_font = ImageFont.truetype(str(find_font(True)), title_size)
    subtitle_font = ImageFont.truetype(str(find_font(False)), subtitle_size)

    scratch = Image.new("RGBA", (1, 1))
    draw = ImageDraw.Draw(scratch)
    title_box = draw.textbbox((0, 0), title, font=title_font)
    title_width = title_box[2] - title_box[0]
    title_height = title_box[3] - title_box[1]
    subtitle_width = 0
    subtitle_height = 0
    if subtitle:
        subtitle_box = draw.textbbox((0, 0), subtitle, font=subtitle_font)
        subtitle_width = subtitle_box[2] - subtitle_box[0]
        subtitle_height = subtitle_box[3] - subtitle_box[1]

    image_width = max(title_width, subtitle_width) + 2 * padding_x
    text_height = title_height + (gap + subtitle_height if subtitle else 0)
    image_height = text_height + 2 * padding_y
    image = Image.new("RGBA", (image_width, image_height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    radius = round(25 * scale)
    draw.rounded_rectangle(
        (0, 0, image_width - 1, image_height - 1),
        radius=radius,
        fill=(18, 18, 18, 188),
    )
    title_y = padding_y - title_box[1]
    draw.text((padding_x, title_y), title, font=title_font, fill="white")
    if subtitle:
        subtitle_x = (image_width - subtitle_width) // 2
        subtitle_y = padding_y + title_height + gap - subtitle_box[1]
        draw.text((subtitle_x, subtitle_y), subtitle, font=subtitle_font, fill="white")
    image.save(output)


def make_banner(output: Path, title: str, width: int, height: int) -> None:
    image = Image.new("RGBA", (width, height), (18, 18, 18, 255))
    draw = ImageDraw.Draw(image)
    font_size = max(34, round(50 * width / 1080))
    font = ImageFont.truetype(str(find_font(True)), font_size)
    text_box = draw.textbbox((0, 0), title, font=font)
    text_width = text_box[2] - text_box[0]
    text_height = text_box[3] - text_box[1]
    x = (width - text_width) // 2 - text_box[0]
    y = (height - text_height) // 2 - text_box[1]
    draw.text((x, y), title, font=font, fill="white")
    image.save(output)


def run(command: Sequence[str]) -> None:
    subprocess.run(command, check=True)


def make_poster(ffmpeg: str, video: Path, poster: Path) -> None:
    run(
        [
            ffmpeg,
            "-nostdin",
            "-y",
            "-v",
            "error",
            "-ss",
            "0.5",
            "-i",
            str(video),
            "-frames:v",
            "1",
            "-q:v",
            "3",
            str(poster),
        ]
    )


def even_scaled_height(source_width: int, source_height: int, target_width: int) -> int:
    return max(2, round(source_height * target_width / source_width / 2) * 2)


def build_wipe(
    ffmpeg: str,
    ffprobe: str,
    spec: WipeSpec,
    output_dir: Path,
    max_width: int,
    crf: int,
) -> None:
    source = VIDEO_DIR / spec.source
    if not source.is_file():
        raise SystemExit(f"Missing packed comparison: {source}")
    metadata = probe(ffprobe, source)
    if metadata["width"] % 2 or metadata["height"] % 2:
        raise SystemExit(f"Packed dimensions must be even: {source}")

    crop_width = metadata["width"] // 2
    crop_height = metadata["height"] // 2
    width = min(max_width, crop_width)
    height = even_scaled_height(crop_width, crop_height, width)
    fps = metadata["fps"]
    duration = metadata["duration"]
    margin = max(18, round(width * 0.013))
    divider_width = max(2, round(width / 475))
    if divider_width % 2:
        divider_width += 1

    with tempfile.TemporaryDirectory(prefix="ridesplat-social-") as temporary:
        temporary_dir = Path(temporary)
        baseline_label = temporary_dir / "baseline.png"
        ours_label = temporary_dir / "ours.png"
        make_label(baseline_label, spec.baseline, None, width)
        make_label(ours_label, "RIDE-Splat (Ours)", None, width)

        baseline_x = spec.column * crop_width
        baseline_y = spec.row * crop_height
        ours_x = crop_width
        ours_y = crop_height
        filter_graph = (
            f"[0:v]split=2[baseline_in][ours_in];"
            f"[baseline_in]crop={crop_width}:{crop_height}:{baseline_x}:{baseline_y},"
            f"scale={width}:{height}:flags=lanczos,setpts=PTS-STARTPTS[baseline];"
            f"[ours_in]crop={crop_width}:{crop_height}:{ours_x}:{ours_y},"
            f"scale={width}:{height}:flags=lanczos,setpts=PTS-STARTPTS[ours];"
            f"[baseline][ours]blend=all_expr='if(lte(X,W/2+W/2*sin(4*PI*T/{duration:.9f})),A,B)'[wipe];"
            f"color=c=white:s={divider_width}x{height}:r={fps.numerator}/{fps.denominator}:"
            f"d={duration:.9f}[line];"
            f"[wipe][line]overlay=x='main_w/2+main_w/2*sin(4*PI*t/{duration:.9f})-overlay_w/2':"
            "y=0:eval=frame[divider];"
            "[1:v]format=rgba[left_label];"
            f"[divider][left_label]overlay=x={margin}:y={margin}:eof_action=repeat[labeled_left];"
            "[2:v]format=rgba[right_label];"
            f"[labeled_left][right_label]overlay=x=main_w-overlay_w-{margin}:y={margin}:"
            "eof_action=repeat[out]"
        )
        output = output_dir / f"ridesplat_{spec.slug}.mp4"
        print(f"Building {output.name}", flush=True)
        run(
            [
                ffmpeg,
                "-nostdin",
                "-y",
                "-v",
                "error",
                "-i",
                str(source),
                "-i",
                str(baseline_label),
                "-i",
                str(ours_label),
                "-filter_complex",
                filter_graph,
                "-map",
                "[out]",
                "-an",
                "-c:v",
                "libx264",
                "-preset",
                "slow",
                "-crf",
                str(crf),
                "-pix_fmt",
                "yuv420p",
                "-r",
                f"{fps.numerator}/{fps.denominator}",
                "-frames:v",
                str(metadata["frames"]),
                "-movflags",
                "+faststart",
                "-map_metadata",
                "-1",
                str(output),
            ]
        )
        make_poster(ffmpeg, output, output_dir / f"ridesplat_{spec.slug}.jpg")


def build_dataset_stack(
    ffmpeg: str,
    ffprobe: str,
    output_dir: Path,
    max_width: int,
    crf: int,
) -> None:
    sources = [VIDEO_DIR / filename for filename, _ in DATASET_ROWS]
    for source in sources:
        if not source.is_file():
            raise SystemExit(f"Missing dataset video: {source}")
    metadata = [probe(ffprobe, source) for source in sources]
    signature = {(item["width"], item["height"], item["fps"]) for item in metadata}
    if len(signature) != 1:
        raise SystemExit(f"Dataset row dimensions/frame rates do not match: {metadata}")
    source_width, source_height, fps = next(iter(signature))
    width = min(max_width, source_width)
    height = even_scaled_height(source_width, source_height, width)
    banner_height = max(80, round(width * 0.09 / 2) * 2)
    frames = min(item["frames"] for item in metadata)

    with tempfile.TemporaryDirectory(prefix="ridesplat-dataset-social-") as temporary:
        temporary_dir = Path(temporary)
        labels = []
        for index, (_, scene) in enumerate(DATASET_ROWS):
            label = temporary_dir / f"label-{index}.png"
            make_label(label, scene, None, width, compact=True)
            labels.append(label)
        banner = temporary_dir / "banner.png"
        make_banner(banner, "RIDE-Splat Dataset", width, banner_height)

        filters = []
        for index in range(3):
            filters.append(
                f"[{index}:v]scale={width}:{height}:flags=lanczos,"
                f"setpts=PTS-STARTPTS[row{index}];"
                f"[{index + 3}:v]format=rgba[label{index}];"
                f"[row{index}][label{index}]overlay=x=(main_w-overlay_w)/2:"
                f"y=(main_h-overlay_h)/2:eof_action=repeat[labeled{index}]"
            )
        filters.append("[6:v]format=yuv420p[banner]")
        filters.append("[banner][labeled0][labeled1][labeled2]vstack=inputs=4[out]")
        output = output_dir / "ridesplat_dataset_three_stack.mp4"
        print(f"Building {output.name}", flush=True)
        command = [ffmpeg, "-nostdin", "-y", "-v", "error"]
        for source in sources:
            command.extend(["-i", str(source)])
        for label in labels:
            command.extend(["-i", str(label)])
        command.extend(
            [
                "-loop",
                "1",
                "-framerate",
                f"{fps.numerator}/{fps.denominator}",
                "-i",
                str(banner),
            ]
        )
        command.extend(
            [
                "-filter_complex",
                ";".join(filters),
                "-map",
                "[out]",
                "-an",
                "-c:v",
                "libx264",
                "-preset",
                "slow",
                "-crf",
                str(crf),
                "-pix_fmt",
                "yuv420p",
                "-r",
                f"{fps.numerator}/{fps.denominator}",
                "-frames:v",
                str(frames),
                "-movflags",
                "+faststart",
                "-map_metadata",
                "-1",
                str(output),
            ]
        )
        run(command)
        make_poster(ffmpeg, output, output_dir / "ridesplat_dataset_three_stack.jpg")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=ROOT / "social",
        help="Output directory (default: %(default)s)",
    )
    parser.add_argument(
        "--only",
        choices=("all", "wipes", "dataset"),
        default="all",
        help="Build only one output group (default: %(default)s)",
    )
    parser.add_argument(
        "--max-width",
        type=int,
        default=1080,
        help="Maximum output width in pixels (default: %(default)s)",
    )
    parser.add_argument(
        "--crf",
        type=int,
        default=20,
        help="H.264 constant-rate factor (default: %(default)s)",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    ffmpeg = require_tool("ffmpeg")
    ffprobe = require_tool("ffprobe")
    if args.max_width < 2:
        raise SystemExit("--max-width must be at least 2")
    if not 0 <= args.crf <= 51:
        raise SystemExit("--crf must be between 0 and 51")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    if args.only in ("all", "wipes"):
        for spec in WIPES:
            build_wipe(ffmpeg, ffprobe, spec, args.output_dir, args.max_width, args.crf)
    if args.only in ("all", "dataset"):
        build_dataset_stack(ffmpeg, ffprobe, args.output_dir, args.max_width, args.crf)
    print(f"Done: {args.output_dir}")


if __name__ == "__main__":
    main()
