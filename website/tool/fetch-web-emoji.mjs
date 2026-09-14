// Fetches Google's Noto Animated Emoji (the app's own reaction set) and writes
// small static WebP frames for the Reaction Playground. Node mirror of the
// Flutter app's tool/fetch_reaction_emoji.py doctrine — see lib/rooms/reactions.dart.
//
// Usage:
//   node tool/fetch-web-emoji.mjs                 fetch, verify, write public/emoji/*.webp
//   node tool/fetch-web-emoji.mjs --print-digests  fetch + print sha256 for every codepoint,
//                                                   write nothing (use to re-pin after a review)
import sharp from "sharp";
import crypto from "node:crypto";
import { readFile, mkdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const WEBSITE_ROOT = path.resolve(__dirname, "..");
const REPO_ROOT = path.resolve(WEBSITE_ROOT, "..");
const DART_REACTIONS_PATH = path.join(REPO_ROOT, "lib/rooms/reactions.dart");
const OUT_DIR = path.join(WEBSITE_ROOT, "public/emoji");

const printDigests = process.argv.includes("--print-digests");

// The website ships all 24 as tiny static frames (not just the 16 Premium-gated
// ones the Flutter app fetches at runtime), so it pins its own digest for every
// codepoint — including the 8 bundled ones, which lib/rooms/reactions.dart never
// pins because the app ships those as build-time assets instead of a CDN fetch.
const WEB_MANIFEST = [
  { emoji: "💖", codepoint: "1f496", label: "Love it", digest: "56a448bb667eab7573047a671f706782b757282e1b737b22abdb2c01fff3f36f" },
  { emoji: "👍", codepoint: "1f44d", label: "Nice", digest: "f456f329ec2457828e0511f31b855e1b3b21c91f53d7d465dc3a1aa7d3b73383" },
  { emoji: "🎉", codepoint: "1f389", label: "Party", digest: "aeff875df341bb7136fa4c84538000a3d4aea8a6dd16245ee8fa1c8bbfeb6ddc" },
  { emoji: "👏", codepoint: "1f44f", label: "Applause", digest: "424f978963357da085a444e1b659028a5f7ccd927d72158ef5c97c82d3ddfd20" },
  { emoji: "😂", codepoint: "1f602", label: "Hilarious", digest: "281d5ceb7881fe9393c200ea16c73a4d53af58b4ff04d76a46c432e7e4dd0901" },
  { emoji: "😮", codepoint: "1f62e", label: "Whoa", digest: "ef22fc1e1f4508a0bb2f5a889fe03d1da5fc528d3d63136e31bf29149c4426b5" },
  { emoji: "😢", codepoint: "1f622", label: "Sad", digest: "d2601ea4398ad6154ace98fb3d786049a92cf6bccd0c9c58a835da72ed5b960a" },
  { emoji: "🤔", codepoint: "1f914", label: "Hmm", digest: "4f8cbd8d563d8bf16d4d7043c3e91afcfe514389bd7e81cc5624f6097aa2053c" },
  { emoji: "🔥", codepoint: "1f525", label: "Fire", digest: "8c18972a71041700a1da4d9a1586640fb6d55eff4dc64efd29efde6a384a2ff5" },
  { emoji: "🍿", codepoint: "1f37f", label: "Popcorn", digest: "38f95c4ba564cb06cf76dbc0cd907b5cb473ac915e2ebf83fc91bf459d9a42ec" },
  { emoji: "🤣", codepoint: "1f923", label: "Rolling", digest: "6dc164b225a4688da15a6642c366e9eb536a0bfb5fe5a475a75c94d2fe14eba5" },
  { emoji: "😍", codepoint: "1f60d", label: "Smitten", digest: "f9a12dd0779299de1c77d8c6168be39ad0f5c579b7ac46f9c77d60be042bc3de" },
  { emoji: "🤯", codepoint: "1f92f", label: "Mind blown", digest: "9bda8e4f7c8941625b0ae64c2c3c85c794bbbe14f8e7bdd13b92b34c726ac59e" },
  { emoji: "😱", codepoint: "1f631", label: "Scream", digest: "960377ff1bbe23d763c32facd45654d1d3b38aaa9d4f5cc4b296bf3c79b9b007" },
  { emoji: "🥳", codepoint: "1f973", label: "Celebrate", digest: "fcf2af3bb9244afe32685f0293ff2ad3f4fb3575e93fec3054f59c052b82762f" },
  { emoji: "🙌", codepoint: "1f64c", label: "Hands up", digest: "51accc877dc32ac4ecfbb5745b89afdf1f610c7e23c4fb292f4bea3dd603fa44" },
  { emoji: "💯", codepoint: "1f4af", label: "Hundred", digest: "c9fdc6075233c9fbd1b77b4df0107187a543223b9ff566fd65a887f221b21008" },
  { emoji: "❤️", codepoint: "2764_fe0f", label: "Heart", digest: "8f02722ca349a1b1a0c7a02d7ec3c716e09eccdbf696adf89c67afe2bb175b56" },
  { emoji: "👀", codepoint: "1f440", label: "Watching", digest: "44da2fbd6e9ec1dee07808fef5216fb8393d78155c7f104be99525215961e07e" },
  { emoji: "😭", codepoint: "1f62d", label: "Sobbing", digest: "13a7a4b7e6d920b83f899ca64312bed80280507e93c04bd6e2361764db975a50" },
  { emoji: "💀", codepoint: "1f480", label: "Dead", digest: "dc404ecc31c03d4c4e5d650300f5b6468b6cc05ca30afa7b483eb07776bef3ed" },
  { emoji: "😴", codepoint: "1f634", label: "Snooze", digest: "ca41f50126de30ef67ae2df42f17ae3fd2ffd7deb7b1bba6d2e4141b1ff2ce3f" },
  { emoji: "🤡", codepoint: "1f921", label: "Clown", digest: "3827a17cc811a5c131a69220eca0d8330135ae1a60184db61cadc6c959d5c58b" },
  { emoji: "🫠", codepoint: "1fae0", label: "Melting", digest: "b641677314fcb258d2114fb84d32c6b5a92a2db984d40c5ab439927cb16126b6" },
];

function parseDartReactions(source) {
  const entries = [];
  const re = /PTReaction\(\s*emoji:\s*'([^']+)',\s*codepoint:\s*'([^']+)',\s*label:\s*'([^']+)'(?:,\s*digest:\s*'([^']+)')?/g;
  let match;
  while ((match = re.exec(source))) {
    entries.push({ emoji: match[1], codepoint: match[2], label: match[3], digest: match[4] });
  }
  return entries;
}

async function crossCheckAgainstDart() {
  const dartSource = await readFile(DART_REACTIONS_PATH, "utf8");
  const dartEntries = parseDartReactions(dartSource);
  const byCodepoint = new Map(dartEntries.map((e) => [e.codepoint, e]));

  if (dartEntries.length !== WEB_MANIFEST.length) {
    throw new Error(
      `Manifest drift: lib/rooms/reactions.dart has ${dartEntries.length} reactions, ` +
        `tool/fetch-web-emoji.mjs has ${WEB_MANIFEST.length}. That list is simultaneously ` +
        `what the app ships and what its receive-side allow-list trusts — refusing to write.`,
    );
  }

  for (const web of WEB_MANIFEST) {
    const dart = byCodepoint.get(web.codepoint);
    if (!dart) {
      throw new Error(`Manifest drift: ${web.codepoint} (${web.emoji}) is not in lib/rooms/reactions.dart.`);
    }
    if (dart.emoji !== web.emoji || dart.label !== web.label) {
      throw new Error(`Manifest drift: ${web.codepoint} does not match lib/rooms/reactions.dart (emoji/label mismatch).`);
    }
    // The Flutter app only pins a digest for its extended (Premium-gated) set — the
    // bundled 8 ship as build-time assets there, so only compare when both sides have
    // one. A mismatch here is a warning, not a refusal: the CDN path is "latest", so
    // Google republishing the asset (confirmed via a manual re-fetch, not a fluke) is
    // the documented normal case, same as the Python tool's own doctrine — it means
    // this website's pin needs a deliberate re-pin, not that the set drifted.
    if (dart.digest && web.digest !== dart.digest) {
      console.warn(
        `Warning: ${web.codepoint} digest differs from lib/rooms/reactions.dart's pin — ` +
          `Google has likely republished the CDN asset since that pin was set. This website's ` +
          `own manifest is the one enforced below; the Flutter app's pin is stale and worth a look.`,
      );
    }
  }
}

async function fetchAndVerify(reaction) {
  const url = `https://fonts.gstatic.com/s/e/notoemoji/latest/${reaction.codepoint}/512.webp`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Fetch failed for ${reaction.codepoint}: HTTP ${res.status}`);
  const bytes = Buffer.from(await res.arrayBuffer());
  const digest = crypto.createHash("sha256").update(bytes).digest("hex");

  if (printDigests) {
    console.log(`${reaction.codepoint}  ${digest}  (${bytes.length} bytes)  ${reaction.emoji} ${reaction.label}`);
    return null;
  }

  if (reaction.digest === "PIN_ME" || !reaction.digest) {
    throw new Error(`${reaction.codepoint} has no pinned digest — run with --print-digests first and pin it.`);
  }
  if (digest !== reaction.digest) {
    throw new Error(
      `Digest mismatch for ${reaction.codepoint}: expected ${reaction.digest}, got ${digest}. ` +
        `Google may have republished the asset — re-pin deliberately via --print-digests after review.`,
    );
  }
  return bytes;
}

// sharp WITHOUT { animated: true } decodes frame 0 only — normally the resting
// frame. A handful of Noto animations instead fade in from a fully transparent
// frame 0 (e.g. 🙌 1f64c), which would ship as a blank tile. Detect that and
// fall back to the first frame with meaningful (non-transparent) coverage.
async function pickRestingFrame(bytes) {
  const candidatePages = [0, 1, 2, 4, 6, 10, 15];
  for (const page of candidatePages) {
    let raw;
    try {
      raw = await sharp(bytes, { page }).resize(96, 96).ensureAlpha().raw().toBuffer();
    } catch {
      break; // ran past the last page
    }
    let opaque = 0;
    for (let i = 3; i < raw.length; i += 4) if (raw[i] > 10) opaque++;
    if (opaque / (raw.length / 4) > 0.05) return page;
  }
  return 0; // couldn't find a better one — ship frame 0 as documented
}

async function main() {
  await crossCheckAgainstDart();
  console.log("Manifest matches lib/rooms/reactions.dart.");

  if (!printDigests) await mkdir(OUT_DIR, { recursive: true });

  for (const reaction of WEB_MANIFEST) {
    const bytes = await fetchAndVerify(reaction);
    if (!bytes) continue; // --print-digests mode
    const dest = path.join(OUT_DIR, `${reaction.codepoint}.webp`);
    const page = await pickRestingFrame(bytes);
    if (page !== 0) console.log(`  (${reaction.codepoint}: frame 0 was blank, using frame ${page})`);
    await sharp(bytes, { page }).resize(96, 96).webp({ quality: 70, effort: 6 }).toFile(dest);
    console.log(`wrote ${path.relative(WEBSITE_ROOT, dest)}`);
  }
}

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
