/**
 * Whether a request may reach the internal metrics dashboard.
 *
 * The dashboard reads production data but is only ever opened from a local
 * `next dev` on the owner's machine, never through the deployed website. So a
 * production build refuses it outright - there is no token, header or host
 * that opens it, which is what makes it safe in an open-source repo (a Host or
 * x-forwarded-for header is trivially spoofed, and a `?token=` in a URL leaks
 * through logs, history and Referer).
 *
 * In development and test, only loopback hosts are admitted.
 */
export function isAuthorizedLocalAccess(
  request: { headers: Headers },
  customEnv?: string
): boolean {
  const env = customEnv || process.env.NODE_ENV;
  if (env !== "development" && env !== "test") return false;

  const host = request.headers.get("host")?.toLowerCase() || "";
  const hostname = host.split(":")[0];

  return (
    hostname === "localhost" ||
    hostname === "127.0.0.1" ||
    hostname === "0.0.0.0" ||
    hostname.endsWith(".localhost") ||
    hostname.endsWith(".local")
  );
}
