// Renders the site's social card, public/og-image.png, from tool/og-image.html.
// Run from website/: node tool/compose-og-image.mjs
// Uses headless Chrome so the card is set in the app's own bundled fonts
// (../assets/fonts) and the real theatre capture (public/shots/room-theater.jpg);
// re-run after recapturing that shot.
import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import { fileURLToPath, pathToFileURL } from "node:url";

const chrome = [
  process.env.CHROME,
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  "/usr/bin/google-chrome",
  "/usr/bin/chromium",
].find((p) => p && existsSync(p));
if (!chrome) {
  console.error("Chrome not found; set CHROME to its binary.");
  process.exit(1);
}

const page = fileURLToPath(new URL("./og-image.html", import.meta.url));
const out = fileURLToPath(new URL("../public/og-image.png", import.meta.url));
execFileSync(chrome, [
  "--headless=new",
  "--hide-scrollbars",
  "--allow-file-access-from-files",
  "--virtual-time-budget=3000",
  "--window-size=1200,630",
  `--screenshot=${out}`,
  pathToFileURL(page).href,
]);
console.log("wrote public/og-image.png");
