#!/usr/bin/env python3
"""Build the production four-direction wardrobe from locked-body sources.

ImageGen sheets are texture donors only. This builder aligns them to the locked
body, splits them into four mutually exclusive runtime slots, derives left by
mirroring right, and writes only the Godot runtime assets and manifests.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps


WORKSPACE = Path(__file__).resolve().parents[2]
PIPELINE_ROOT = WORKSPACE / "tools/character-paper-doll-pipeline"
BODY_SOURCE_ROOT = PIPELINE_ROOT / "sources/wardrobe_v1/body"
BODY_SHEET = WORKSPACE / "game/assets/characters/anchor_hd_demo/body_walk_hd_640x1024.png"
SOURCE_OUTFITS_ROOT = PIPELINE_ROOT / "sources/wardrobe_v1/outfits"
RUNTIME_ROOT = WORKSPACE / "game/assets/characters/anchor_hd_demo/hero_wardrobe"

BODY_SHEET_SHA256 = "2C971E6EDEA6891E9B6077A17D3F31756557942AD5BD6C4F6B06B6AFD2458F92"
SOURCE_SHEET_SIZE = (3072, 1536)
SOURCE_FRAME_SIZE = (1024, 1536)
RUNTIME_FRAME_SIZE = (640, 1024)
RUNTIME_ROOT_POINT = (320, 960)
TARGET_BODY_HEIGHT = 896
POSES = ("neutral", "step_left", "step_right")
ROW_SEQUENCE = ("neutral", "step_left", "neutral", "step_right")
DIRECTIONS = ("down", "right", "up", "left")
GENERATED_DIRECTIONS = ("down", "right", "up")
SLOTS = ("head", "top_hands", "bottom", "shoes")

OUTFITS = {
    "red_blue_acrobat": {
        "displayName": "红蓝飞索客",
        "sources": {
            "down": SOURCE_OUTFITS_ROOT / "red_blue_acrobat/down.png",
            "right": SOURCE_OUTFITS_ROOT / "red_blue_acrobat/right.png",
            "up": SOURCE_OUTFITS_ROOT / "red_blue_acrobat/up.png",
        },
    },
    "navy_guard": {
        "displayName": "深蓝守卫",
        "sources": {
            "down": SOURCE_OUTFITS_ROOT / "navy_guard/down.png",
            "right": SOURCE_OUTFITS_ROOT / "navy_guard/right.png",
            "up": SOURCE_OUTFITS_ROOT / "navy_guard/up.png",
        },
    },
    "emerald_ogre": {
        "displayName": "翡翠巨怪",
        "sources": {
            "down": SOURCE_OUTFITS_ROOT / "emerald_ogre/down.png",
            "right": SOURCE_OUTFITS_ROOT / "emerald_ogre/right.png",
            "up": SOURCE_OUTFITS_ROOT / "emerald_ogre/up.png",
        },
    },
}

LOCKED_BODY_MASK_CACHE: dict[tuple[str, str, str], np.ndarray] = {}


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def alpha_bbox(image: Image.Image) -> tuple[int, int, int, int]:
    bbox = image.convert("RGBA").getchannel("A").getbbox()
    if bbox is None:
        raise ValueError("Image has no visible pixels")
    return bbox


def dilate_binary_mask(mask: np.ndarray, size: int) -> np.ndarray:
    """Fast square dilation for large authoring masks."""
    radius = size // 2
    padded = np.pad(mask.astype(np.uint8), radius, mode="constant")
    integral = (
        np.pad(padded, ((1, 0), (1, 0)), mode="constant")
        .cumsum(0, dtype=np.int64)
        .cumsum(1, dtype=np.int64)
    )
    height, width = mask.shape
    window = (
        integral[size : size + height, size : size + width]
        - integral[:height, size : size + width]
        - integral[size : size + height, :width]
        + integral[:height, :width]
    )
    return window > 0


def body_transform(body: Image.Image) -> dict[str, object]:
    bbox = alpha_bbox(body)
    crop = body.crop(bbox)
    scale = TARGET_BODY_HEIGHT / crop.height
    head_limit = max(1, round(crop.height * 0.24))
    head_bbox = crop.getchannel("A").crop((0, 0, crop.width, head_limit)).getbbox()
    head_center = crop.width / 2.0 if head_bbox is None else (head_bbox[0] + head_bbox[2]) / 2.0
    paste_x = round(RUNTIME_ROOT_POINT[0] - head_center * scale)
    paste_y = RUNTIME_ROOT_POINT[1] - TARGET_BODY_HEIGHT
    return {"bbox": bbox, "scale": scale, "paste": (paste_x, paste_y)}


def apply_body_transform(layer: Image.Image, transform: dict[str, object]) -> Image.Image:
    bbox = transform["bbox"]
    scale = float(transform["scale"])
    paste = transform["paste"]
    assert isinstance(bbox, tuple)
    assert isinstance(paste, tuple)
    destination_x = float(paste[0]) - float(bbox[0]) * scale
    destination_y = float(paste[1]) - float(bbox[1]) * scale
    inverse = (
        1.0 / scale,
        0.0,
        -destination_x / scale,
        0.0,
        1.0 / scale,
        -destination_y / scale,
    )
    return layer.transform(
        RUNTIME_FRAME_SIZE,
        Image.Transform.AFFINE,
        inverse,
        resample=Image.Resampling.BICUBIC,
        fillcolor=(0, 0, 0, 0),
    )


def align_to_body(panel: Image.Image, body: Image.Image) -> tuple[Image.Image, tuple[int, int]]:
    subject_bbox = alpha_bbox(panel)
    body_bbox = alpha_bbox(body)
    subject_center = (subject_bbox[0] + subject_bbox[2]) / 2.0
    body_center = (body_bbox[0] + body_bbox[2]) / 2.0
    dx = round(body_center - subject_center)
    dy = body_bbox[3] - subject_bbox[3]
    aligned = Image.new("RGBA", SOURCE_FRAME_SIZE, (0, 0, 0, 0))
    aligned.alpha_composite(panel, (dx, dy))
    aligned_bbox = alpha_bbox(aligned)
    if aligned_bbox[3] != body_bbox[3]:
        raise ValueError(f"Foot baseline mismatch after alignment: {aligned_bbox} vs {body_bbox}")
    return aligned, (dx, dy)


def fit_to_locked_body(
    panel: Image.Image,
    body: Image.Image,
) -> tuple[Image.Image, dict[str, object]]:
    """Uniformly fit an ImageGen donor to the locked master's height and root.

    ImageGen is never allowed to define runtime scale or foot placement. The
    donor is resized to the exact master height, centered on the master, and
    grounded on the master's lowest visible pixel before any slot is cut.
    """
    subject_bbox = alpha_bbox(panel)
    body_bbox = alpha_bbox(body)
    subject = panel.crop(subject_bbox)
    target_height = body_bbox[3] - body_bbox[1]
    scale = target_height / subject.height
    resized = subject.resize(
        (max(1, round(subject.width * scale)), target_height),
        Image.Resampling.LANCZOS,
    )
    body_center = (body_bbox[0] + body_bbox[2]) / 2.0
    paste_x = round(body_center - resized.width / 2.0)
    paste_y = body_bbox[3] - resized.height
    fitted = Image.new("RGBA", SOURCE_FRAME_SIZE, (0, 0, 0, 0))
    fitted.alpha_composite(resized, (paste_x, paste_y))
    return fitted, {
        "scale": scale,
        "paste": [paste_x, paste_y],
        "sourceBBox": list(subject_bbox),
    }


def constrain_slot_to_locked_body(
    layer: Image.Image,
    body: Image.Image,
    slot: str,
    cache_key: tuple[str, str, str],
) -> Image.Image:
    """Keep donor pixels only near the exact locked-body silhouette.

    The small dilation is wardrobe allowance (hair, hood, cuffs and soles),
    not a second body silhouette. It prevents a generated donor from changing
    limb length, body width, pose, or root placement.
    """
    allowance = {
        "head": 81,
        "top_hands": 41,
        "bottom": 35,
        "shoes": 41,
    }[slot]
    if cache_key not in LOCKED_BODY_MASK_CACHE:
        body_alpha = np.asarray(body.convert("RGBA"), dtype=np.uint8)[:, :, 3]
        expanded = dilate_binary_mask(body_alpha > 0, allowance)
        LOCKED_BODY_MASK_CACHE[cache_key] = np.where(expanded, 255, 0).astype(np.uint8)
    rgba = np.asarray(layer.convert("RGBA"), dtype=np.uint8).copy()
    allowed = LOCKED_BODY_MASK_CACHE[cache_key]
    rgba[:, :, 3] = np.minimum(rgba[:, :, 3], allowed)

    rgba[rgba[:, :, 3] == 0, :3] = 0
    return Image.fromarray(rgba, "RGBA")


def split_slots(
    image: Image.Image,
    body: Image.Image,
    outfit_id: str,
) -> dict[str, Image.Image]:
    body_bbox = alpha_bbox(body)
    rgba = np.asarray(image.convert("RGBA"), dtype=np.uint8)
    alpha = rgba[:, :, 3] > 0
    body_alpha = np.asarray(body.convert("RGBA"), dtype=np.uint8)[:, :, 3] > 0
    height = body_bbox[3] - body_bbox[1]
    center_x = (body_bbox[0] + body_bbox[2]) / 2.0
    body_width = body_bbox[2] - body_bbox[0]
    # Semantic seams: neck root, hip/crotch transition, and the real shoe upper.
    # The old broad horizontal bands cut through the chest and trouser cuffs.
    head_cut = body_bbox[1] + round(height * 0.205)
    waist_y = body_bbox[1] + round(height * 0.50)
    hand_bottom = body_bbox[1] + round(height * 0.64)
    center_half = body_width * 0.34

    yy, xx = np.indices((SOURCE_FRAME_SIZE[1], SOURCE_FRAME_SIZE[0]))
    head_mask = alpha & (yy < head_cut)
    shoes_region = np.zeros_like(alpha)
    lower_leg_y = body_bbox[1] + round(height * 0.61)
    shoe_height = round(height * 0.16)
    horizontal_margin = round(height * 0.035)
    center_column = round(center_x)
    for half_left, half_right in ((0, center_column), (center_column, SOURCE_FRAME_SIZE[0])):
        half_mask = body_alpha.copy()
        half_mask[:lower_leg_y, :] = False
        half_mask[:, :half_left] = False
        half_mask[:, half_right:] = False
        leg_y, leg_x = np.where(half_mask)
        if leg_x.size == 0:
            continue
        foot_bottom = int(leg_y.max()) + 1
        shoe_top = max(0, foot_bottom - shoe_height)
        x0 = max(0, int(leg_x.min()) - horizontal_margin)
        x1 = min(SOURCE_FRAME_SIZE[0], int(leg_x.max()) + 1 + horizontal_margin)
        shoes_region[shoe_top:foot_bottom, x0:x1] = True
    red = rgba[:, :, 0].astype(np.float32)
    green = rgba[:, :, 1].astype(np.float32)
    blue = rgba[:, :, 2].astype(np.float32)
    if outfit_id == "red_blue_acrobat":
        shoe_seed = (red > 55.0) & (red > green * 2.0) & (red > blue * 1.8)
    elif outfit_id == "navy_guard":
        shoe_seed = (
            (red > 35.0)
            & (red < green * 2.8)
            & (red > blue * 1.45)
            & (green > blue * 1.05)
        )
    else:
        shoe_seed = (
            (green > red * 1.12)
            & (green > blue * 1.05)
            & (red < 90.0)
            & (green < 125.0)
        )
    shoe_seed &= alpha & shoes_region
    expanded_seed = dilate_binary_mask(shoe_seed, 15)
    shoes_mask = alpha & shoes_region & expanded_seed
    hand_band = alpha & (yy >= waist_y) & (yy < hand_bottom)
    if outfit_id == "red_blue_acrobat":
        hand_seed = (red > 70.0) & (red > green * 1.65) & (red > blue * 1.35)
    elif outfit_id == "navy_guard":
        hand_seed = (
            (red > 120.0)
            & (red > green * 1.08)
            & (green > blue * 1.08)
        )
    else:
        hand_seed = (
            (green > red * 1.12)
            & (green > blue * 1.10)
            & (green > 70.0)
        )
    hand_seed &= hand_band
    hand_mask = dilate_binary_mask(hand_seed, 7) & hand_band

    # Slots are mutually exclusive. There are no color/body fallback layers:
    # absent donor pixels stay transparent.
    bottom_mask = alpha & (yy >= waist_y) & ~hand_mask & ~shoes_mask
    upper_body_mask = alpha & (yy >= head_cut) & (yy < waist_y)
    top_mask = (upper_body_mask | hand_mask) & ~shoes_mask

    masks = {
        "head": head_mask,
        "top_hands": top_mask,
        "bottom": bottom_mask,
        "shoes": shoes_mask,
    }
    output: dict[str, Image.Image] = {}
    for slot, mask in masks.items():
        slot_rgba = rgba.copy()
        slot_rgba[:, :, 3] = np.where(mask, rgba[:, :, 3], 0)
        slot_rgba[slot_rgba[:, :, 3] == 0, :3] = 0
        output[slot] = Image.fromarray(slot_rgba, "RGBA")
    return output


def pack_sheet(frames: dict[str, dict[str, Image.Image]]) -> Image.Image:
    sheet = Image.new("RGBA", (2560, 4096), (0, 0, 0, 0))
    for row, direction in enumerate(DIRECTIONS):
        for column, pose in enumerate(ROW_SEQUENCE):
            sheet.alpha_composite(frames[direction][pose], (column * 640, row * 1024))
    return sheet


def main() -> None:
    if sha256_file(BODY_SHEET) != BODY_SHEET_SHA256:
        raise ValueError("Locked body sheet changed")
    RUNTIME_ROOT.mkdir(parents=True, exist_ok=True)

    slot_frames: dict[str, dict[str, dict[str, dict[str, Image.Image]]]] = {}

    for outfit_id, config in OUTFITS.items():
        source_paths = {direction: Path(path) for direction, path in config["sources"].items()}
        slot_frames[outfit_id] = {
            slot: {direction: {} for direction in DIRECTIONS}
            for slot in SLOTS
        }
        for direction in GENERATED_DIRECTIONS:
            raw_sheet = Image.open(source_paths[direction]).convert("RGBA").resize(
                SOURCE_SHEET_SIZE, Image.Resampling.LANCZOS
            )
            for panel_index, pose in enumerate(POSES):
                panel = raw_sheet.crop(
                    (panel_index * 1024, 0, (panel_index + 1) * 1024, 1536)
                )
                body = Image.open(BODY_SOURCE_ROOT / direction / f"{pose}.png").convert("RGBA")
                if direction == "down":
                    aligned, shift = align_to_body(panel, body)
                    alignment: dict[str, object] = {"translation": list(shift)}
                else:
                    aligned, alignment = fit_to_locked_body(panel, body)
                transform = body_transform(body)
                split = split_slots(aligned, body, outfit_id)
                for slot, source_layer in split.items():
                    constrained = constrain_slot_to_locked_body(
                        source_layer,
                        body,
                        slot,
                        (direction, pose, slot),
                    )
                    runtime_layer = apply_body_transform(constrained, transform)
                    slot_frames[outfit_id][slot][direction][pose] = runtime_layer

        for pose in POSES:
            for slot in SLOTS:
                mirrored = ImageOps.mirror(slot_frames[outfit_id][slot]["right"][pose])
                slot_frames[outfit_id][slot]["left"][pose] = mirrored

        runtime_outfit = RUNTIME_ROOT / outfit_id
        runtime_outfit.mkdir(parents=True, exist_ok=True)
        for slot in SLOTS:
            pack_sheet(slot_frames[outfit_id][slot]).save(runtime_outfit / f"{slot}_walk_hd_640x1024.png")
        manifest = {
            "schemaVersion": 1,
            "assetId": outfit_id,
            "displayName": config["displayName"],
            "animationScope": "four_directions_three_unique_frames",
            "runtimeFrame": [640, 1024],
            "root": [320, 960],
            "sheet": [2560, 4096],
            "directions": list(DIRECTIONS),
            "directionRows": {direction: row for row, direction in enumerate(DIRECTIONS)},
            "leftMirrorsRight": True,
            "slots": {slot: f"{slot}_walk_hd_640x1024.png" for slot in SLOTS},
            "rowSequence": list(ROW_SEQUENCE),
            "bodySheetSha256": BODY_SHEET_SHA256,
        }
        (runtime_outfit / "outfit_manifest.json").write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )

    print(json.dumps({
        "runtimeRoot": str(RUNTIME_ROOT.relative_to(WORKSPACE)).replace("\\", "/"),
        "outfits": list(OUTFITS),
        "bodySheetSha256": sha256_file(BODY_SHEET),
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
