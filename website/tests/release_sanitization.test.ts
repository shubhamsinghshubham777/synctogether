import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { sanitizeReleaseBody } from "../lib/github.ts";

describe("sanitizeReleaseBody", () => {
  it("returns empty string for empty input", () => {
    assert.equal(sanitizeReleaseBody(""), "");
  });

  it("leaves release notes without macOS installation notes untouched", () => {
    const body = "## What's Changed\n- Added feature A\n- Fixed bug B\n\n## Downloads\n- Windows\n- macOS";
    assert.equal(sanitizeReleaseBody(body), body);
  });

  it("strips obsolete unsigned macOS installation notes section", () => {
    const rawBody = `## What's Changed
- Added feature A

## Downloads
- **Windows**: \`SyncTogether-1.2.0-Windows.exe\`
- **macOS**: \`SyncTogether-1.2.0-macOS.dmg\`

## macOS Installation Notes
This build is unsigned. To run the app:
1. Open the DMG and drag SyncTogether to Applications
2. Right-click the app and select "Open" (first time only)
3. Or run: \`xattr -cr /Applications/SyncTogether.app\`
`;

    const expected = `## What's Changed
- Added feature A

## Downloads
- **Windows**: \`SyncTogether-1.2.0-Windows.exe\`
- **macOS**: \`SyncTogether-1.2.0-macOS.dmg\``;

    assert.equal(sanitizeReleaseBody(rawBody), expected);
  });

  it("strips macOS and Windows installation notes sections", () => {
    const rawBody = `## Downloads
- **macOS**: \`SyncTogether.dmg\`

## macOS Installation Notes
This build is signed with Apple Developer ID and notarized by Apple.
1. Open the DMG and drag SyncTogether to Applications
2. Double-click to open.`;

    const expected = `## Downloads
- **macOS**: \`SyncTogether.dmg\``;

    assert.equal(sanitizeReleaseBody(rawBody), expected);
  });
});
