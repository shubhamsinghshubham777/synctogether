// One-off compositing step for the generated OG background plate.
// Run: node tool/compose-og-image.mjs <path-to-plate.png>
// Requires "Space Grotesk" to be resolvable by the system font stack (librsvg/Pango).
import sharp from "sharp";

const [, , platePath] = process.argv;
if (!platePath) {
  console.error("usage: node tool/compose-og-image.mjs <plate.png>");
  process.exit(1);
}

const W = 1200;
const H = 630;

const ICON_X = 96;
const ICON_Y = 73;
const ICON_SIZE = 64;

const overlay = `
<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">
  <defs>
    <linearGradient id="iconGrad" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#8B5CF6"/>
      <stop offset="1" stop-color="#C084FC"/>
    </linearGradient>
    <linearGradient id="textGrad" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#C9B8FF"/>
      <stop offset="1" stop-color="#C084FC"/>
    </linearGradient>
  </defs>
  <g transform="translate(${ICON_X}, ${ICON_Y})">
    <rect width="${ICON_SIZE}" height="${ICON_SIZE}" rx="20.5" fill="url(#iconGrad)"/>
    <path d="M25.5 20.4V43.6C25.5 45.6 27.6 46.8 29.3 45.9L48.1 34.3C49.8 33.2 49.8 30.8 48.1 29.7L29.3 18.1C27.6 17.2 25.5 18.4 25.5 20.4Z" fill="#FFFFFF"/>
  </g>
  <text
    x="${ICON_X + ICON_SIZE + 18}"
    y="${ICON_Y + ICON_SIZE / 2 + 14}"
    font-family="Space Grotesk"
    font-weight="700"
    font-size="42"
    fill="#FFFFFF"
  >Sync<tspan fill="url(#textGrad)">Together</tspan></text>
  <text
    x="${ICON_X + 2}"
    y="${ICON_Y + ICON_SIZE + 56}"
    font-family="Space Grotesk"
    font-weight="500"
    font-size="24"
    fill="#D8D2E8"
  >Watch together, in perfect sync.</text>
</svg>`;

await sharp(platePath)
  .resize(W, H, { fit: "cover" })
  .composite([{ input: Buffer.from(overlay) }])
  .png({ quality: 90 })
  .toFile("public/og-image.png");

console.log("wrote public/og-image.png");
