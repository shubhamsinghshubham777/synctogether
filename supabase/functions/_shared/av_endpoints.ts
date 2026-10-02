// LiveKit-protocol endpoints, in priority order. Kept apart from index.ts so
// it can be tested without serving a request.

export type AvEndpoint = { id: string; url: string; key: string; secret: string };

export function parseEndpoints(env: Record<string, string | undefined>): AvEndpoint[] {
  const raw = env["LIVEKIT_ENDPOINTS"];
  if (raw && raw.trim() !== "") {
    let parsed: unknown;
    try {
      parsed = JSON.parse(raw);
    } catch {
      throw new Error("LIVEKIT_ENDPOINTS is not valid JSON");
    }
    if (!Array.isArray(parsed)) throw new Error("LIVEKIT_ENDPOINTS must be a JSON array");
    const seen = new Set<string>();
    return parsed.map((e, i) => {
      const { id, url, key, secret } = (e ?? {}) as Record<string, unknown>;
      for (const [name, v] of Object.entries({ id, url, key, secret })) {
        if (typeof v !== "string" || v === "") {
          throw new Error(`LIVEKIT_ENDPOINTS[${i}].${name} is missing`);
        }
      }
      if (seen.has(id as string)) throw new Error(`LIVEKIT_ENDPOINTS id "${id}" is repeated`);
      seen.add(id as string);
      return { id, url, key, secret } as AvEndpoint;
    });
  }
  const url = env["LIVEKIT_URL"];
  const key = env["LIVEKIT_API_KEY"];
  const secret = env["LIVEKIT_API_SECRET"];
  if (!url || !key || !secret) return [];
  return [{ id: "default", url, key, secret }];
}

/// RoomServiceClient speaks HTTP; endpoints are configured as the ws(s) URL
/// clients dial.
export function httpHost(url: string): string {
  return url.replace(/^ws(s?):\/\//, "http$1://");
}
