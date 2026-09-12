"""Generate the app icon.

Committed as a script rather than only as a PNG so the icon can be regenerated
at any size and tweaked in a reviewable diff.

The mark is the measurement screen's own progress ring around a heart, so the
icon on the home screen is the thing the user sees while measuring, rather
than unrelated stock imagery. Deliberately no ECG trace: the app never renders
a fake waveform, and the icon should not imply one either.

    python tools/make_icon.py
"""

import math
import os

from PIL import Image, ImageDraw

SIZE = 1024
OUT = os.path.join(os.path.dirname(__file__),
                   "..", "App", "Resources", "Assets.xcassets",
                   "AppIcon.appiconset", "AppIcon-1024.png")

BACKGROUND_TOP = (28, 27, 33)
BACKGROUND_BOTTOM = (16, 15, 19)
ACCENT = (217, 56, 79)          # matches Theme.accent
RING_TRACK = (58, 56, 66)


# The heart curve is not symmetric about its origin: it runs to about +13 at
# the lobes and -17 at the point. Centring it in the ring means shifting by
# half that difference, otherwise it sits low and crowds the bottom of the arc.
HEART_TOP = 13.0
HEART_BOTTOM = -17.0
HEART_CENTRE_OFFSET = (HEART_TOP + HEART_BOTTOM) / 2.0
HEART_HALF_EXTENT = (HEART_TOP - HEART_BOTTOM) / 2.0


def heart_points(cx, cy, scale, steps=720):
    """Classic heart curve, scaled and flipped into image coordinates."""
    points = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        x = 16 * math.sin(t) ** 3
        y = (13 * math.cos(t) - 5 * math.cos(2 * t)
             - 2 * math.cos(3 * t) - math.cos(4 * t))
        points.append((cx + x * scale, cy - (y - HEART_CENTRE_OFFSET) * scale))
    return points


def main():
    image = Image.new("RGB", (SIZE, SIZE), BACKGROUND_TOP)
    draw = ImageDraw.Draw(image)

    # Vertical gradient background.
    for y in range(SIZE):
        blend = y / (SIZE - 1)
        draw.line(
            [(0, y), (SIZE, y)],
            fill=tuple(
                int(BACKGROUND_TOP[c] + (BACKGROUND_BOTTOM[c] - BACKGROUND_TOP[c]) * blend)
                for c in range(3)
            ),
        )

    # Supersample the artwork, then downscale, so the curves stay smooth
    # without needing an antialiasing library.
    scale_factor = 4
    big = Image.new("RGBA", (SIZE * scale_factor, SIZE * scale_factor), (0, 0, 0, 0))
    big_draw = ImageDraw.Draw(big)

    centre = SIZE * scale_factor / 2
    radius = SIZE * scale_factor * 0.34
    width = int(SIZE * scale_factor * 0.045)
    box = [centre - radius, centre - radius, centre + radius, centre + radius]

    # Full track, then the accent arc over roughly three quarters of it --
    # the same partial-progress look as the measurement ring.
    big_draw.arc(box, 0, 360, fill=RING_TRACK + (255,), width=width)
    big_draw.arc(box, -90, 190, fill=ACCENT + (255,), width=width)

    # Size the heart from the ring's inner edge so it always clears the arc,
    # rather than from a constant that has to be re-tuned whenever the ring
    # geometry changes.
    inner_radius = radius - width / 2.0
    heart_scale = (inner_radius * 0.70) / HEART_HALF_EXTENT
    big_draw.polygon(
        heart_points(centre, centre, heart_scale),
        fill=ACCENT + (255,),
    )

    artwork = big.resize((SIZE, SIZE), Image.LANCZOS)
    image.paste(artwork, (0, 0), artwork)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    # No alpha channel: App Store Connect rejects icons with transparency.
    image.convert("RGB").save(OUT, "PNG")
    print(f"wrote {os.path.normpath(OUT)} ({SIZE}x{SIZE})")


if __name__ == "__main__":
    main()
