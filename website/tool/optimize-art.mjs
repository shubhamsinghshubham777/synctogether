// npm i -D sharp   (devDependency only — never ships to the client)
import sharp from "sharp";
import { readdir, unlink } from "node:fs/promises";
import { join, parse } from "node:path";

const JOBS = [
  { dir: "public/film", sizes: [[1600, 900], [800, 450]], quality: 50 },
  { dir: "public/avatars", sizes: [[256, 256]], quality: 55 },
  { dir: "public/art", sizes: [[1200, 800]], quality: 50 },
];

for (const { dir, sizes, quality } of JOBS) {
  for (const file of await readdir(dir)) {
    if (!/\.(png|jpe?g)$/i.test(file)) continue;
    const { name } = parse(file);
    for (const [w, h] of sizes) {
      const suffix = sizes.length > 1 && w < sizes[0][0] ? "-sm" : "";
      const dest = join(dir, `${name}${suffix}.avif`);
      await sharp(join(dir, file))
        .resize(w, h, { fit: "cover" })
        .avif({ quality, effort: 6 })
        .toFile(dest);
      console.log(`wrote ${dest}`);
    }
    await unlink(join(dir, file));
    console.log(`removed source ${file}`);
  }
}

// The avatar art is composed for a circular mask - outside the circle it is pure
// white, so it cannot simply be stretched into a rectangular facecam tile. Derive a
// wide crop that stays *inside* that circle instead: the largest 16:9 rectangle
// inscribed in a 256px circle is 222x125, raised 14px because a head-and-shoulders
// portrait puts the face above centre. Runs off the committed .avif rather than the
// discarded source, so it stays reproducible after the sources are unlinked.
// Only the two the facecam rail actually renders as a feed - the rest of the set is
// used circle-masked and needs no crop, and generating unused art just orphans it.
const CAM = { width: 222, height: 125, lift: 14, out: [444, 250] };
const CAM_SUBJECTS = ["av-01", "av-02"];

for (const name of CAM_SUBJECTS) {
  const src = join("public/avatars", `${name}.avif`);
  const meta = await sharp(src).metadata();
  const dest = join("public/avatars", `${name}-cam.avif`);
  await sharp(src)
    .extract({
      left: Math.round((meta.width - CAM.width) / 2),
      top: Math.round((meta.height - CAM.height) / 2) - CAM.lift,
      width: CAM.width,
      height: CAM.height,
    })
    .resize(CAM.out[0], CAM.out[1])
    .avif({ quality: 55, effort: 6 })
    .toFile(dest);
  console.log(`wrote ${dest}`);
}
