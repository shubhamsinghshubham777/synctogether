"""Build the Creem checkout branding art in assets/brand/creem/.

Creem's checkout takes a store logo (52x52 shown, upload larger for retina) and
a storefront banner (1920x400). Both are drawn from the same sources as the app
so they cannot drift: the logo is the "s·t" tile (assets/icon/app_icon_square.svg)
and the banner sets the wordmark - "sync" + Beam dot + "together", Bricolage
Grotesque 800 at -3.5% tracking, as PTWordmark (lib/ui/logo.dart) does - on a
Booth field, outlines lifted straight out of the bundled font.

    pip install fonttools          # plus rsvg-convert (brew install librsvg)
    python3 tool/generate_creem_branding.py

Colours are the PTColors tokens (see lib/ui/pt_theme.dart); no gradients.
"""

import os
import subprocess
import sys

from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "assets", "brand", "creem")
FONTS = os.path.join(ROOT, "assets", "fonts")

BOOTH = "#121010"
RAIL = "#3A332E"
SCREEN = "#F4ECDF"
BEAM = "#FFB23F"
MUTE = "#8F8476"  # PTColors.fgMute

W, H = 1920, 400


def outlines(font_path, text, size, tracking_em, colors):
    """Return (svg path elements, advance width) for `text` at `size` px,
    baseline at y=0, each character coloured by `colors[i]`."""
    font = TTFont(font_path)
    upem = font["head"].unitsPerEm
    glyphs = font.getGlyphSet()
    cmap = font.getBestCmap()
    scale = size / upem
    x = 0.0
    parts = []
    for ch, color in zip(text, colors):
        name = cmap[ord(ch)]
        pen = SVGPathPen(glyphs)
        glyphs[name].draw(TransformPen(pen, (scale, 0, 0, -scale, x, 0)))
        d = pen.getCommands()
        if d:
            parts.append(f'<path d="{d}" fill="{color}"/>')
        x += glyphs[name].width * scale + tracking_em * size
    return parts, x


def mono_caps(text, size, tracking_em):
    return outlines(
        os.path.join(FONTS, "JetBrainsMono-400.ttf"), text, size, tracking_em, [MUTE] * len(text)
    )


def banner_svg():
    word = "sync·together"
    colors = [SCREEN if c != "·" else BEAM for c in word]
    size = 168
    wm, wm_w = outlines(
        os.path.join(FONTS, "BricolageGrotesque-800.ttf"), word, size, -0.035, colors
    )
    cap, cap_w = mono_caps("WATCH TOGETHER, PERFECTLY IN SYNC", 26, 0.18)
    # Centred: the storefront crops a wide banner on narrow screens, and the
    # middle is what survives.
    left = (W - wm_w) / 2
    cap_left = (W - cap_w) / 2
    base = 214  # wordmark baseline
    svg = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
        f'<rect width="{W}" height="{H}" fill="{BOOTH}"/>',
        # A single Rail hairline along the bottom: the booth's one flat rule.
        f'<rect x="0" y="{H - 2}" width="{W}" height="2" fill="{RAIL}"/>',
        f'<g transform="translate({left} {base})">{"".join(wm)}</g>',
        f'<g transform="translate({cap_left} {base + 78})">{"".join(cap)}</g>',
        "</svg>",
    ]
    return "\n".join(svg)


def render(svg_path, png_path, width=None):
    cmd = ["rsvg-convert", svg_path, "-o", png_path]
    if width:
        cmd[1:1] = ["-w", str(width), "-h", str(width)]
    subprocess.run(cmd, check=True)


os.makedirs(OUT, exist_ok=True)
with open(os.path.join(OUT, "banner.svg"), "w") as f:
    f.write(banner_svg())
render(os.path.join(OUT, "banner.svg"), os.path.join(OUT, "banner_1920x400.png"))

square = os.path.join(ROOT, "assets", "icon", "app_icon_square.svg")
render(square, os.path.join(OUT, "logo_512.png"), 512)
render(square, os.path.join(OUT, "logo_256.png"), 256)
print("wrote", OUT)
