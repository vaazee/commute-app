#!/usr/bin/env python3
"""Generate the CommuteApp iOS app icon (1024x1024, opaque)."""
from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
OUT = Path(__file__).resolve().parent.parent / "CommuteApp" / "Assets.xcassets" / "AppIcon.appiconset" / "icon-1024.png"

PATH_BLUE = (0, 61, 165)
NJT_ORANGE = (245, 128, 37)
WHITE = (255, 255, 255)
WINDSHIELD = (20, 40, 80)


def diagonal_gradient(size: int, c1: tuple[int, int, int], c2: tuple[int, int, int]) -> Image.Image:
    img = Image.new("RGB", (size, size), c1)
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1))
            px[x, y] = (
                round(c1[0] + (c2[0] - c1[0]) * t),
                round(c1[1] + (c2[1] - c1[1]) * t),
                round(c1[2] + (c2[2] - c1[2]) * t),
            )
    return img


def rounded_rect(draw: ImageDraw.ImageDraw, bbox, radius: int, fill):
    draw.rounded_rectangle(bbox, radius=radius, fill=fill)


def draw_bus(base: Image.Image) -> None:
    overlay = Image.new("RGBA", base.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)

    # Bus body (front-facing). Centered, slight breathing room for iOS masking.
    body_w = 620
    body_h = 760
    body_x = (SIZE - body_w) // 2
    body_y = (SIZE - body_h) // 2 + 20

    # Soft shadow beneath the bus.
    shadow = Image.new("RGBA", base.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.ellipse(
        (body_x - 20, body_y + body_h - 40, body_x + body_w + 20, body_y + body_h + 60),
        fill=(0, 0, 0, 110),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=22))
    overlay.alpha_composite(shadow)

    d = ImageDraw.Draw(overlay)
    rounded_rect(d, (body_x, body_y, body_x + body_w, body_y + body_h), radius=80, fill=WHITE + (255,))

    # Destination sign strip (NJT-orange accent across the top).
    sign_margin = 40
    sign_y = body_y + 50
    sign_h = 70
    rounded_rect(
        d,
        (body_x + sign_margin, sign_y, body_x + body_w - sign_margin, sign_y + sign_h),
        radius=18,
        fill=NJT_ORANGE + (255,),
    )

    # Windshield (large rounded rect below the sign).
    ws_top = sign_y + sign_h + 40
    ws_h = 260
    ws_margin = 60
    rounded_rect(
        d,
        (body_x + ws_margin, ws_top, body_x + body_w - ws_margin, ws_top + ws_h),
        radius=40,
        fill=WINDSHIELD + (255,),
    )
    # Windshield highlight (diagonal gleam).
    gleam = Image.new("RGBA", base.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(gleam)
    gd.polygon(
        [
            (body_x + ws_margin + 30, ws_top + ws_h - 20),
            (body_x + ws_margin + 150, ws_top + 20),
            (body_x + ws_margin + 210, ws_top + 20),
            (body_x + ws_margin + 90, ws_top + ws_h - 20),
        ],
        fill=(255, 255, 255, 55),
    )
    overlay.alpha_composite(gleam)

    d = ImageDraw.Draw(overlay)

    # Grille / front panel separator.
    grille_y = ws_top + ws_h + 50
    rounded_rect(
        d,
        (body_x + 90, grille_y, body_x + body_w - 90, grille_y + 30),
        radius=12,
        fill=(210, 210, 210, 255),
    )

    # Headlights.
    hl_y = grille_y + 70
    hl_r = 40
    hl_left_x = body_x + 140
    hl_right_x = body_x + body_w - 140
    for cx in (hl_left_x, hl_right_x):
        d.ellipse((cx - hl_r, hl_y - hl_r, cx + hl_r, hl_y + hl_r), fill=(255, 230, 140, 255))
        d.ellipse((cx - hl_r + 10, hl_y - hl_r + 10, cx + hl_r - 10, hl_y + hl_r - 10), fill=(255, 250, 210, 255))

    # Bumper.
    bumper_y = body_y + body_h - 70
    rounded_rect(
        d,
        (body_x + 40, bumper_y, body_x + body_w - 40, bumper_y + 40),
        radius=18,
        fill=(60, 60, 70, 255),
    )

    # Wheels peeking out at the bottom.
    wheel_r = 55
    wheel_y = body_y + body_h - 10
    for cx in (body_x + 130, body_x + body_w - 130):
        d.ellipse((cx - wheel_r, wheel_y - wheel_r, cx + wheel_r, wheel_y + wheel_r), fill=(30, 30, 35, 255))
        d.ellipse((cx - 22, wheel_y - 22, cx + 22, wheel_y + 22), fill=(120, 120, 130, 255))

    base.paste(overlay, (0, 0), overlay)


def main() -> None:
    img = diagonal_gradient(SIZE, PATH_BLUE, NJT_ORANGE).convert("RGBA")
    draw_bus(img)
    final = img.convert("RGB")  # strip alpha — iOS rejects transparent app icons.
    OUT.parent.mkdir(parents=True, exist_ok=True)
    final.save(OUT, format="PNG", optimize=True)
    print(f"Wrote {OUT} ({OUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
