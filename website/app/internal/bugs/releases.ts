import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { promisify } from "node:util";
import { parsePubspecVersion, parseTagVersions, releaseOptions } from "@/lib/bug_board_logic";

const run = promisify(execFile);

/**
 * The versions a fix can ship in: the one in pubspec.yaml (the build being
 * worked on) and the recent release tags. The board only ever runs from a local
 * checkout (see lib/admin-guard.ts), so the repo is right there to read; if it
 * is not, the dropdown simply falls back to the free-text field.
 */
export async function loadReleaseOptions(): Promise<{ value: string; label: string }[]> {
  const repo = path.resolve(process.cwd(), "..");
  const [current, tags] = await Promise.all([
    readFile(path.join(repo, "pubspec.yaml"), "utf8")
      .then(parsePubspecVersion)
      .catch(() => null),
    run("git", ["tag", "--sort=-v:refname"], { cwd: repo, timeout: 4000 })
      .then(({ stdout }) => parseTagVersions(stdout))
      .catch(() => [] as string[]),
  ]);
  return releaseOptions(current, tags);
}
