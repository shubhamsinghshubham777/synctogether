"""Build the SyncTogether app-icon source art in assets/icon/.

The art is `PTLogoMark` (lib/ui/logo.dart): the wordmark compressed to "s·t",
Screen letters (PTColors.fg, #F4ECDF) with a Beam middle dot (PTColors.primary,
#FFB23F) on a Booth tile (PTColors.canvas, #121010). The letter outlines are
lifted straight out of the Bricolage Grotesque 800 the app bundles, so the icon
and the on-screen mark can never drift apart.

    pip install fonttools          # plus rsvg-convert (brew install librsvg)
    python3 tool/generate_app_icon.py
    fvm dart run flutter_launcher_icons

Usage: generate_app_icon.py [font.ttf] [out_dir]
"""

import os
import subprocess
import sys
import tempfile

from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_FONT = os.path.join(ROOT, "assets", "fonts", "BricolageGrotesque-800.ttf")

FONT = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_FONT
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "assets", "icon")

TILE = "#121010"  # PTColors.canvas (Booth)
INK = "#F4ECDF"  # PTColors.fg (Screen)
BEAM = "#FFB23F"  # PTColors.primary
RADIUS_RATIO = 0.24  # PTLogoMark's corner radius
# PTLogoMark sets the letters at 46% of the tile; the icon runs them a little
# larger, since at 16-32 px the mark is all there is to read.
TEXT_RATIO = 0.56
TRACKING = -0.02  # of the font size, as PTLogoMark's letterSpacing
SIZE = 1024

font = TTFont(FONT)
upem = font["head"].unitsPerEm
glyphs = font.getGlyphSet()
cmap = font.getBestCmap()
hmtx = font["hmtx"]


def glyph_runs(text):
    """[(glyph name, x offset in font units)] for `text`, tracked."""
    x = 0
    runs = []
    for ch in text:
        name = cmap[ord(ch)]
        runs.append((name, x))
        x += hmtx[name][0] + TRACKING * upem
    return runs


RUNS = glyph_runs("s\u00b7t")

# Ink bounds of the whole mark, so it centres optically on its outlines rather
# than on advance widths (the dot's side bearings would pull it off-centre).
_bounds = BoundsPen(glyphs)
for _name, _x in RUNS:
    glyphs[_name].draw(TransformPen(_bounds, (1, 0, 0, 1, _x, 0)))
XMIN, YMIN, XMAX, YMAX = _bounds.bounds


def glyph_path(name):
    pen = SVGPathPen(glyphs)
    glyphs[name].draw(pen)
    return pen.getCommands()


def art(tile, rounded=True, glyph=True, bg=True, mono=False):
    """SVG for a SIZE canvas holding a `tile`-wide icon tile, centred."""
    pad = (SIZE - tile) / 2
    r = tile * RADIUS_RATIO if rounded else 0
    scale = tile * TEXT_RATIO / upem
    # Font y grows upward from the baseline; SVG y grows downward.
    tx = SIZE / 2 - (XMIN + XMAX) / 2 * scale
    ty = SIZE / 2 + (YMIN + YMAX) / 2 * scale
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}" '
        f'viewBox="0 0 {SIZE} {SIZE}">'
    ]
    if bg:
        parts.append(
            f'<rect x="{pad}" y="{pad}" width="{tile}" height="{tile}" '
            f'rx="{r}" ry="{r}" fill="{TILE}"/>'
        )
    if glyph:
        parts.append(f'<g transform="translate({tx} {ty}) scale({scale} {-scale})">')
        for name, x in RUNS:
            fill = INK if mono or name != cmap[0xB7] else BEAM
            parts.append(
                f'<path transform="translate({x} 0)" d="{glyph_path(name)}" fill="{fill}"/>'
            )
        parts.append("</g>")
    parts.append("</svg>")
    return "\n".join(parts)


def render(svg_path, png_path, size):
    subprocess.run(
        ["rsvg-convert", "-w", str(size), "-h", str(size), svg_path, "-o", png_path],
        check=True,
    )


def write(basename, svg):
    svg_path = os.path.join(OUT, basename + ".svg")
    png_path = os.path.join(OUT, basename + ".png")
    with open(svg_path, "w") as fh:
        fh.write(svg)
    render(svg_path, png_path, SIZE)
    print("wrote", os.path.relpath(png_path, ROOT))
    return svg_path


def write_ico(svg_path, ico_path, sizes=(16, 24, 32, 48, 64, 128, 256)):
    """Multi-size .ico, each frame rasterised from the vector.

    flutter_launcher_icons only emits a single 256px frame, which leaves the
    taskbar and Explorer's small views downscaling a 256px bitmap.
    """
    frames = []
    with tempfile.TemporaryDirectory() as tmp:
        for size in sizes:
            frame = os.path.join(tmp, f"{size}.png")
            render(svg_path, frame, size)
            frames.append(frame)
        subprocess.run(["magick", *frames, ico_path], check=True)
    print("wrote", os.path.relpath(ico_path, ROOT))


os.makedirs(OUT, exist_ok=True)

master = write("app_icon", art(SIZE))
write_ico(master, os.path.join(ROOT, "windows", "runner", "resources", "app_icon.ico"))

# iOS and macOS 26+ both round the corners themselves, so they share square
# full-bleed art. Anything less than full bleed is actively wrong on macOS 26:
# the system treats transparency as "legacy icon" and drops the artwork onto a
# default light-grey container, which reads as a grey border in the Dock.
write("app_icon_square", art(SIZE, rounded=False))

# Android adaptive layers are full-bleed: flutter_launcher_icons wraps the
# foreground and monochrome drawables in its own 16% safe-zone inset, so
# pre-shrinking them here would shrink the glyph twice. The corner radius lives
# on the background layer only - the launcher mask does the real rounding.
write("app_icon_background", art(SIZE, rounded=False, glyph=False))
write("app_icon_foreground", art(SIZE, bg=False))
write("app_icon_monochrome", art(SIZE, bg=False, mono=True))

# Microsoft Store listing logos. The store shows them as drawn, never masked,
# so they get the rounded master like the Windows .ico.
for size in (150, 300):
    dest = os.path.join(ROOT, "assets", "store", f"store_logo_{size}x{size}.png")
    render(master, dest, size)
    print("wrote", os.path.relpath(dest, ROOT))

# Marketing website favicons and icons
website_app = os.path.join(ROOT, "website", "app")
website_public = os.path.join(ROOT, "website", "public")
if os.path.isdir(website_app):
    import shutil

    # Multi-resolution favicon.ico (16, 32, 48) for web
    write_ico(master, os.path.join(website_app, "favicon.ico"), sizes=(16, 32, 48))
    write_ico(master, os.path.join(website_public, "favicon.ico"), sizes=(16, 32, 48))

    # Vector SVG favicon for modern browsers
    shutil.copyfile(master, os.path.join(website_app, "icon.svg"))
    shutil.copyfile(master, os.path.join(website_public, "icon.svg"))

    # Apple Touch Icon (180x180)
    apple_icon_app = os.path.join(website_app, "apple-icon.png")
    apple_icon_pub = os.path.join(website_public, "apple-touch-icon.png")
    render(master, apple_icon_app, 180)
    render(master, apple_icon_pub, 180)
    print("wrote", os.path.relpath(apple_icon_app, ROOT))
    print("wrote", os.path.relpath(apple_icon_pub, ROOT))

    # 1024x1024 full PNG for OpenGraph / Organization schema
    icon_pub = os.path.join(website_public, "icon.png")
    render(master, icon_pub, SIZE)
    print("wrote", os.path.relpath(icon_pub, ROOT))

