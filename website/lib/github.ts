export interface GitHubAsset {
  id: number;
  name: string;
  browser_download_url: string;
  size: number;
  content_type: string;
  download_count: number;
}

export interface GitHubRelease {
  id: number;
  tag_name: string;
  name: string;
  body: string;
  published_at: string;
  prerelease: boolean;
  draft: boolean;
  html_url: string;
  assets: GitHubAsset[];
}

export interface ReleaseAssetInfo {
  version: string;
  tagName: string;
  name: string;
  publishedAt: string;
  macDownloadUrl: string;
  macSizeMb: number;
  winDownloadUrl: string;
  winSizeMb: number;
  body: string;
  htmlUrl: string;
}

// Only for download links when GitHub is unreachable: it points at the releases
// page rather than naming a version, so it can never go stale or lie. UI that
// shows a version must use fetchLatestRelease() and hide itself on null.
const RELEASES_PAGE = "https://github.com/shubhamsinghshubham777/synctogether/releases/latest";
const FALLBACK_RELEASE: ReleaseAssetInfo = {
  version: "",
  tagName: "",
  name: "",
  publishedAt: "",
  macDownloadUrl: RELEASES_PAGE,
  macSizeMb: 0,
  winDownloadUrl: RELEASES_PAGE,
  winSizeMb: 0,
  body: "",
  htmlUrl: RELEASES_PAGE,
};

/**
 * Strips OS installation notes (e.g. macOS Installation Notes, Windows Installation Notes)
 * from release bodies, as normal installation is the default user expectation.
 */
export function sanitizeReleaseBody(body: string): string {
  if (!body) return "";
  return body
    .replace(
      /##+\s*(?:macOS|Windows)\s+Installation\s+Notes[\s\S]*?(?=(?:##+\s*|$))/gi,
      ""
    )
    .trim();
}

/**
 * Unauthenticated GitHub calls share a 60/hour limit per IP, which serverless
 * hosts exhaust easily. A failed call used to bake the stale fallback into the
 * cached page for an hour, so authenticate when a token is configured.
 */
function githubHeaders(): Record<string, string> {
  const token = process.env.GITHUB_TOKEN;
  return {
    Accept: "application/vnd.github.v3+json",
    "User-Agent": "SyncTogether-Website",
    ...(token ? { Authorization: `Bearer ${token}` } : {}),
  };
}

export async function getLatestRelease(): Promise<ReleaseAssetInfo> {
  return (await fetchLatestRelease()) ?? FALLBACK_RELEASE;
}

/** The latest stable release, or null when GitHub did not give a real answer. */
export async function fetchLatestRelease(): Promise<ReleaseAssetInfo | null> {
  try {
    const res = await fetch(
      "https://api.github.com/repos/shubhamsinghshubham777/synctogether/releases/latest",
      { next: { revalidate: 3600 }, headers: githubHeaders() }
    );

    if (!res.ok) {
      // Throw so a revalidating page keeps its last good render instead of
      // caching the fallback; the catch below still covers cold starts.
      throw new Error(`GitHub releases/latest answered ${res.status}`);
    }

    const data: GitHubRelease = await res.json();
    const rawVersion = data.name || data.tag_name;
    const cleanVersion = rawVersion.replace(/^v/, "").replace(/_\d+$/, "");
    const titleName = data.name ? data.name.replace(/_\d+$/, "") : `v${cleanVersion}`;

    const macAsset = data.assets.find(
      (a) => a.name.endsWith(".dmg") || a.name.includes("macOS")
    );
    const winAsset = data.assets.find(
      (a) => a.name.endsWith(".exe") || a.name.includes("Windows")
    );

    return {
      version: cleanVersion,
      tagName: data.tag_name,
      name: titleName,
      publishedAt: data.published_at,
      macDownloadUrl:
        macAsset?.browser_download_url ||
        `https://github.com/shubhamsinghshubham777/synctogether/releases/download/${data.tag_name}/SyncTogether-${cleanVersion}-macOS.dmg`,
      macSizeMb: macAsset ? Math.round((macAsset.size / (1024 * 1024)) * 10) / 10 : 42.5,
      winDownloadUrl:
        winAsset?.browser_download_url ||
        `https://github.com/shubhamsinghshubham777/synctogether/releases/download/${data.tag_name}/SyncTogether-${cleanVersion}-Windows.exe`,
      winSizeMb: winAsset ? Math.round((winAsset.size / (1024 * 1024)) * 10) / 10 : 38.2,
      body: sanitizeReleaseBody(data.body || ""),
      htmlUrl: data.html_url,
    };
  } catch (error) {
    console.error("Error fetching latest GitHub release:", error);
    return null;
  }
}

export async function getAllReleases(): Promise<GitHubRelease[]> {
  try {
    const res = await fetch(
      "https://api.github.com/repos/shubhamsinghshubham777/synctogether/releases?per_page=30",
      { next: { revalidate: 3600 }, headers: githubHeaders() }
    );

    if (!res.ok) {
      return [];
    }

    const releases: GitHubRelease[] = await res.json();
    // Filter out drafts and pre-releases as specified in the plan, and sanitize obsolete unsigned notes from historical bodies
    return releases
      .filter((r) => !r.draft && !r.prerelease)
      .map((r) => ({
        ...r,
        body: sanitizeReleaseBody(r.body || ""),
      }));
  } catch (error) {
    console.error("Error fetching all releases:", error);
    return [];
  }
}
