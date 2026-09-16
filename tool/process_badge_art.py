#!/usr/bin/env python3
"""Turn flat-black badge renders into the transparent art in assets/badges/.

    python3 tool/process_badge_art.py <renders-dir> assets/badges 256

Needs Pillow, numpy and scipy (unlike the other tools here, which are stdlib
only) - keying glowing artwork needs real image ops:

    python3 -m venv /tmp/badges && /tmp/badges/bin/pip install Pillow numpy scipy

The *source renders are not in the repo* - eighteen 2048px PNGs is ~90 MB, and
they are regenerable. Point the first argument at wherever they live. The
prompts that produced them are in docs/gamification-plan.md.

The art is generated, so `assets/badges/*.png` is build output: change this
script and re-run it, never hand-edit a PNG.

Why the renders are black rather than transparent
-------------------------------------------------
The image model cannot emit an alpha channel at all. Asked for a transparent
PNG it paints a *picture of a checkerboard* - the UI symbol for transparency -
as opaque pixels, which is unusable. Asking for flat pure black instead is both
achievable and better: luminance then *is* the alpha, so a glow fades out
naturally rather than being hard-keyed into a fringe.
"""

from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage
import numpy as np
import sys, os, glob

SRC = sys.argv[1]
DST = sys.argv[2]
SIZE = int(sys.argv[3]) if len(sys.argv) > 3 else 256

# Below this the pixel is background, not glow. The renders put the background
# at 0-9 and the glyphs at 250+, so there is a lot of room here.
CORE = 16
# Luminance at which glow becomes fully opaque; below it, proportional.
GLOW_FULL = 110

os.makedirs(DST, exist_ok=True)


def alpha_for(im):
    lum = np.asarray(im.convert('L')).astype(np.int16)

    # 1. Silhouette, with interior holes closed.
    core = Image.fromarray(((lum > CORE) * 255).astype('uint8'), 'L')
    core = core.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(5))
    # Flood the *outside* from all four corners; whatever the flood cannot reach
    # is enclosed by the glyph and belongs to it, however dark it is.
    holes = core.copy()
    for xy in [(0, 0), (core.width - 1, 0), (0, core.height - 1),
               (core.width - 1, core.height - 1)]:
        ImageDraw.floodfill(holes, xy, 128, thresh=10)
    filled = np.asarray(core).astype(np.int16)
    filled[np.asarray(holes) != 128] = 255

    # 2. Drop anything that is not the glyph. The decorative corner sparkle is
    #    its own island, and keeping it means a stray dot in every tile.
    labels, count = ndimage.label(filled > 0)
    if count > 1:
        areas = ndimage.sum(filled > 0, labels, range(1, count + 1))
        keep = {i + 1 for i, a in enumerate(areas) if a >= areas.max() * 0.05}
        filled = np.where(np.isin(labels, list(keep)), filled, 0)

    # 3. Soft glow falloff, so the halo blends over the tile behind it. Masked
    #    to the glyph's own neighbourhood so the sparkle's halo goes with it.
    near = ndimage.binary_dilation(filled > 0, iterations=24)
    glow = np.clip(lum.astype(float) * 255.0 / GLOW_FULL, 0, 255) * near

    return np.maximum(filled, glow).astype('uint8')


def content_box(alpha):
    """Bounding box of the glyph, ignoring the corner sparkle."""
    small = Image.fromarray(alpha, 'L').resize((96, 96), Image.BOX)
    a = np.asarray(small)
    ys, xs = np.where(a > 40)
    if len(xs) == 0:
        return None
    sx = alpha.shape[1] / 96.0
    sy = alpha.shape[0] / 96.0
    return (int(xs.min() * sx), int(ys.min() * sy),
            int((xs.max() + 1) * sx), int((ys.max() + 1) * sy))


print(f"{'file':<20} {'crop':<22} {'out':>10}")
print('-' * 56)
for p in sorted(glob.glob(os.path.join(SRC, '*.png'))):
    name = os.path.basename(p)
    im = Image.open(p).convert('RGB')
    alpha = alpha_for(im)

    box = content_box(alpha)
    if box is None:
        print(f'{name:<20} SKIPPED - no content'); continue
    x0, y0, x1, y1 = box

    # Square around the glyph's centre, with a little breathing room, so every
    # badge sits at the same visual weight in the grid.
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    side = int(max(x1 - x0, y1 - y0) * 1.10)
    half = side // 2
    sx0, sy0 = cx - half, cy - half

    out = Image.new('RGBA', (side, side), (0, 0, 0, 0))
    src = Image.merge('RGBA', (*im.split(), Image.fromarray(alpha, 'L')))
    out.paste(src.crop((sx0, sy0, sx0 + side, sy0 + side)), (0, 0))
    out = out.resize((SIZE, SIZE), Image.LANCZOS)

    # Premultiplied-looking fringes come from resampling colour where alpha is
    # zero; black there is harmless because the art is already dark-cored.
    dest = os.path.join(DST, name)
    out.save(dest, optimize=True)
    print(f'{name:<20} {f"{x1-x0}x{y1-y0} -> {side}":<22} '
          f'{os.path.getsize(dest)//1024:>8}KB')
