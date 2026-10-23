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
