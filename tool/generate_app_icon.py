"""Build the SyncTogether app-icon source art in assets/icon/.

The art mirrors the in-app wordmark logo (`_Wordmark` in
lib/rooms/lobby_screen.dart): a rounded square filled with
PTColors.brandGradient (top-left -> bottom-right, #8B5CF6 -> #C084FC), corner
radius 32% of the tile, and a white Icons.play_arrow_rounded glyph at 55%. The
glyph outline is lifted straight out of the MaterialIcons font the app ships
with, so the icon and the on-screen logo can never drift apart.

    pip install fonttools          # plus rsvg-convert (brew install librsvg)
    python3 tool/generate_app_icon.py
    fvm dart run flutter_launcher_icons

Usage: generate_app_icon.py [font.otf] [out_dir]
"""

import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_FONT = os.path.join(
    ROOT, ".fvm", "flutter_sdk", "bin", "cache", "artifacts", "material_fonts",
    "MaterialIcons-Regular.otf",
)

FONT = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_FONT
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "assets", "icon")

CODEPOINT = 0xF00A0  # Icons.play_arrow_rounded
GRAD_START = "#8B5CF6"  # PTColors.primary
GRAD_END = "#C084FC"  # PTColors.gradientEnd
RADIUS_RATIO = 0.32
GLYPH_RATIO = 0.55
SIZE = 1024

try:
    from fontTools.pens.svgPathPen import SVGPathPen
    from fontTools.ttLib import TTFont

    font = TTFont(FONT)
    upem = font["head"].unitsPerEm
    glyphs = font.getGlyphSet()
    pen = SVGPathPen(glyphs)
    glyphs[font.getBestCmap()[CODEPOINT]].draw(pen)
    GLYPH_PATH = pen.getCommands()
except (ImportError, FileNotFoundError):
    upem = 512
    GLYPH_PATH = "M171 367V145C171 129 189 118 204 128L377 238C390 246 390 266 377 274L204 384C189 394 171 383 171 367Z"





def art(tile, rounded=True, glyph=True, bg=True):
    """SVG for a SIZE canvas holding a `tile`-wide icon tile, centred."""
    pad = (SIZE - tile) / 2
    em = tile * GLYPH_RATIO
    scale = em / upem
    offset = (SIZE - em) / 2
    r = tile * RADIUS_RATIO if rounded else 0
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}" '
        f'viewBox="0 0 {SIZE} {SIZE}">',
        "<defs>"
        f'<linearGradient id="g" x1="{pad}" y1="{pad}" x2="{pad + tile}" y2="{pad + tile}" '
        f'gradientUnits="userSpaceOnUse">'
        f'<stop offset="0" stop-color="{GRAD_START}"/>'
        f'<stop offset="1" stop-color="{GRAD_END}"/>'
        "</linearGradient></defs>",
    ]
    if bg:
        parts.append(
            f'<rect x="{pad}" y="{pad}" width="{tile}" height="{tile}" '
            f'rx="{r}" ry="{r}" fill="url(#g)"/>'
        )
    if glyph:
        # Font y grows upward from the baseline; SVG y grows downward.
        parts.append(
            f'<g transform="translate({offset} {offset + em}) scale({scale} {-scale})">'
            f'<path d="{GLYPH_PATH}" fill="#FFFFFF"/></g>'
        )
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
write("app_icon_monochrome", art(SIZE, bg=False))

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

