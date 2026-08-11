#!/usr/bin/env python3

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


FRAME_SOURCE_SIZE = 400
FRAME_RUNTIME_SIZE = 40
CONTENT_SOURCE_SIZE = 352


def _arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Normalize a transparent action icon into runtime frames.",
    )
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--strip-out", required=True, type=Path)
    parser.add_argument("--preview-out", type=Path)
    parser.add_argument("--frame-count", type=int, choices=(1, 2), default=2)
    return parser.parse_args()


def _normalized_frame(
    source: Image.Image,
    frame_index: int,
    frame_count: int,
) -> Image.Image:
    source_width, source_height = source.size
    frame_width = source_width // frame_count
    left = frame_index * frame_width
    frame = source.crop((left, 0, left + frame_width, source_height))
    content_bounds = frame.getchannel("A").getbbox()
    if content_bounds is None:
        raise ValueError(f"frame {frame_index} has no visible pixels")
    content = frame.crop(content_bounds)
    content.thumbnail(
        (CONTENT_SOURCE_SIZE, CONTENT_SOURCE_SIZE),
        Image.Resampling.NEAREST,
    )
    normalized = Image.new(
        "RGBA",
        (FRAME_SOURCE_SIZE, FRAME_SOURCE_SIZE),
        (0, 0, 0, 0),
    )
    normalized.alpha_composite(
        content,
        (
            (FRAME_SOURCE_SIZE - content.width) // 2,
            (FRAME_SOURCE_SIZE - content.height) // 2,
        ),
    )
    return normalized


def main() -> None:
    args = _arguments()
    source = Image.open(args.input).convert("RGBA")
    if source.width % args.frame_count != 0:
        raise ValueError("source width must be divisible by frame count")

    strip = Image.new(
        "RGBA",
        (FRAME_SOURCE_SIZE * args.frame_count, FRAME_SOURCE_SIZE),
        (0, 0, 0, 0),
    )
    for frame_index in range(args.frame_count):
        strip.alpha_composite(
            _normalized_frame(source, frame_index, args.frame_count),
            (frame_index * FRAME_SOURCE_SIZE, 0),
        )

    runtime_strip = strip.resize(
        (FRAME_RUNTIME_SIZE * args.frame_count, FRAME_RUNTIME_SIZE),
        Image.Resampling.LANCZOS,
    )
    args.strip_out.parent.mkdir(parents=True, exist_ok=True)
    runtime_strip.save(args.strip_out)
    if args.preview_out is not None:
        args.preview_out.parent.mkdir(parents=True, exist_ok=True)
        runtime_strip.save(args.preview_out)

    if runtime_strip.getpixel((0, 0))[3] != 0:
        raise ValueError("normalized strip corner must be transparent")


if __name__ == "__main__":
    main()
