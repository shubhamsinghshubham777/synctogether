# Badge artwork prompts

The prompts that produced `assets/badges/*.png`. The source renders are not in the repo (~90 MB), so regenerate from these, then run `tool/process_badge_art.py`.


`assets/badges/*.png` (18 files, 256px, ~1.2 MB total) is **build output**. Change
`tool/process_badge_art.py` and re-run it; never hand-edit a PNG.

```bash
python3 -m venv /tmp/badges && /tmp/badges/bin/pip install Pillow numpy scipy
/tmp/badges/bin/python tool/process_badge_art.py <renders-dir> assets/badges 256
```

The source renders are **not in the repo** - eighteen 2048px PNGs is ~90 MB, and
they are regenerable from the prompts below.

### Why the renders are black, not transparent

The image model cannot emit an alpha channel. Asked for a transparent PNG it
paints a *picture of a checkerboard* - the UI symbol for transparency - as opaque
pixels. The first attempt came back that way and was unusable.

Asking for **flat pure black** instead is both achievable and better for glowing
artwork: luminance then *is* the alpha, so a glow fades out naturally instead of
being hard-keyed into a fringe. Two wrinkles the script handles:

- A glyph can contain genuinely dark pixels - `devoted` has a near-black
  checkmark on a gold calendar - so the silhouette is flood-filled from the
  border first and everything enclosed is forced opaque. Keying on luminance
  alone punches a hole straight through it.
- Every render carries a decorative corner sparkle. It is dropped by connected
  components: anything unattached to the glyph and under a twentieth of its area
  is a speck, and a speck that survives is a stray dot in a 40px tile.

### What the prompts must say

Learned the hard way, and all four matter:

1. **Flat pure black background**, never "transparent".
2. **Bare glyph - no tile, frame, badge, container or border.** `BadgeTile`
   already draws a tile; art that carries its own nests a tile in a tile,
   which the design system forbids and which looks muddy.
3. **One bold silhouette, no scenes.** These render at **40px**. The first
   attempt asked for a laurel wreath *plus* a film reel, a ring of ten figures, a
   calendar with grid lines - all mush at that size.
4. **Generate one reference, then attach it to every other prompt, scoped to
   texture only.** The model is an image *editor* at heart, so a reference gives
   consistency that independent prompts never will. It also copies *subjects*: told
   only "same style, replace the symbol", it drew a clapperboard with the reference
   handshake still inside it. Every follow-up therefore describes its own symbol in
   full, says the attachment is a reference for ink texture only, and forbids hands
   outright. A fresh chat per badge helps when it still leaks.
5. **Attach the downloaded file, never a screenshot**: a screenshot's rounded frame
   and the generator's sparkle watermark leak into the next render. The watermark
   that does appear is dropped by the speck filter, and so is any part of a glyph
   that does not touch the rest (`night_owl` lost its second star that way), so ask
   for one connected shape.

The projection booth set is **flat rubber-stamp ink**, one colour per badge, slightly
rotated: the "stamps" of the Components board. Colours are Cue teal #6FD6C4 for the
sync badges (`first_sync`, `perfect_sync`), Brass #E8C877 for the gold ones
(`unbroken`, `century`, `devoted`, `season_1`), Screen #F4ECDF for `season_2`,
bronze #C98A5A for `season_3`, and Signal coral #FF6A4D for everything else.

The reference prompt (`first_sync`):

> A single icon symbol printed like a rubber ink stamp on a solid pure black
> background. The symbol is two hands clasped in a handshake, drawn as one bold,
> thick, simplified flat silhouette with no fine detail, readable at 40 pixels. Flat
> matte ink in one solid colour, teal #6FD6C4, with a slightly imperfect
> hand-stamped texture: faint grain, a few tiny ink gaps and slightly uneven edges,
> like a real rubber stamp pressed firmly onto paper. The whole symbol is rotated
> about 6 degrees. Completely flat: no gradient, no glow, no shine, no 3D, no bevel,
> no shadow, no lighting effects. The symbol is centred and fills about 80% of the
> frame. Square 1:1 image. The background is flat pure black #000000 with nothing
> else in it: no circle, no ring, no stamp border, no tile, no rounded square, no
> frame, no container, no card, no checkerboard, no text, no letters, no numbers.

Every other badge, with the reference attached:

> Draw a brand new icon: SUBJECT. It is one bold, thick, simplified flat
> silhouette, readable at 40 pixels, centred and filling about 80% of a square 1:1
> frame, rotated about ANGLE degrees. Print it as a rubber ink stamp in one solid
> flat ink colour, COLOUR, on a flat pure black #000000 background. The attached
> image is ONLY a reference for the ink texture: copy its faint grain, tiny ink gaps
> and slightly uneven stamped edges, and nothing else. Do NOT copy its subject. The
> image must contain no handshake, no hands, no fingers and no arms, only the
> SUBJECT. No gradient, no glow, no 3D, no shadow, no tile, no frame, no border, no
> text, no letters, no numbers.

Subjects: bullseye with an arrow · single flame · upward arrow with a flame trail ·
lightning bolt through an unbroken ring · two overlapping clapperboards · three
head-and-shoulders figures · hourglass · crescent moon with two stars · three
interlocking rings · laurel wreath · party popper with attached confetti · game
controller · three speech bubbles · calendar page with a checkmark cut out · trophy
cup (gold / silver / bronze).

The processed files are **palette PNGs** (256 colours including alpha, about 8 KB
each): one flat ink colour is visually lossless in a palette, at under a fifth of the
RGBA size. Not JPEG, which has no alpha and rings around hard ink edges.

### Locked badges

Rendered dimmed and desaturated rather than behind a padlock: the shape stays
recognisable, which is the point of showing somebody what they have not earned.
The progress ring already says "not yet", so a padlock would say it twice. A
badge with **no** art still falls back to its Material Symbol, and to a padlock
when locked - `achievements` is a database table, so the catalogue is allowed to
run ahead of the client.
