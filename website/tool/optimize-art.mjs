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
