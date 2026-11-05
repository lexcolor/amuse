"""Derives the launcher-icon sources every platform needs from the web icons.

    python tool/icon/make_sources.py && dart run flutter_launcher_icons

web/icons/Icon-maskable-512.png (full-bleed gradient + glyph) is split into
an Android adaptive background (gradient only) and foreground (white glyph on
transparent, inside the safe zone); web/icons/Icon-512.png (rounded) is
padded for macOS, whose icons sit inside a margin.
"""
from pathlib import Path

from PIL import Image

root = Path(__file__).resolve().parents[2]
out = root / "tool" / "icon"
maskable = Image.open(root / "web/icons/Icon-maskable-512.png").convert("RGBA")
rounded = Image.open(root / "web/icons/Icon-512.png").convert("RGBA")
S = 1024

# --- Adaptive background: rebuild the diagonal gradient from the corners.
tl, br = maskable.getpixel((4, 4)), maskable.getpixel((507, 507))
bg = Image.new("RGBA", (S, S))
px = bg.load()
for y in range(S):
    for x in range(S):
        t = (x + y) / (2 * (S - 1))
        px[x, y] = tuple(round(tl[i] + (br[i] - tl[i]) * t) for i in range(3)) + (255,)
bg.save(out / "adaptive_background.png")

# --- Adaptive foreground: the white glyph, alpha taken from its whiteness
# (the gradient's green channel stays below ~170; the glyph is 255).
fg = Image.new("RGBA", maskable.size, (0, 0, 0, 0))
src, dst = maskable.load(), fg.load()
for y in range(maskable.height):
    for x in range(maskable.width):
        g = src[x, y][1]
        a = max(0, min(255, round((g - 180) * 255 / 75)))
        dst[x, y] = (255, 255, 255, a)
# Android shows the centre 66% of the 108dp canvas; the glyph already sits
# well inside that in the maskable icon, so scale the whole square to fit.
canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
canvas.alpha_composite(fg.resize((S, S), Image.LANCZOS))
canvas.save(out / "adaptive_foreground.png")

# --- macOS: rounded icon at 80% on a transparent 1024 canvas.
inner = round(S * 0.8)
mac = Image.new("RGBA", (S, S), (0, 0, 0, 0))
mac.alpha_composite(rounded.resize((inner, inner), Image.LANCZOS), ((S - inner) // 2, (S - inner) // 2))
mac.save(out / "macos.png")
print("wrote", [p.name for p in sorted(out.glob("*.png"))])
