// LiveKit-protocol endpoints, in priority order. Kept apart from index.ts so
// it can be tested without serving a request.

/// `trial`: whether the free tier's video trial may run here. Trial video is
/// only cheap on a server we run ourselves, so it defaults to on everywhere
/// except LiveKit Cloud, which bills by the minute; set it explicitly to
/// override either way.
export type AvEndpoint = { id: string; url: string; key: string; secret: string; trial: boolean };

function defaultTrial(url: string): boolean {
  return !/\.livekit\.cloud(?::\d+)?(?:\/|$)/i.test(url);
}

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
      const { id, url, key, secret, trial } = (e ?? {}) as Record<string, unknown>;
      for (const [name, v] of Object.entries({ id, url, key, secret })) {
        if (typeof v !== "string" || v === "") {
          throw new Error(`LIVEKIT_ENDPOINTS[${i}].${name} is missing`);
        }
      }
      if (seen.has(id as string)) throw new Error(`LIVEKIT_ENDPOINTS id "${id}" is repeated`);
      if (trial !== undefined && typeof trial !== "boolean") {
        throw new Error(`LIVEKIT_ENDPOINTS[${i}].trial must be true or false`);
      }
      seen.add(id as string);
      return {
        id,
        url,
        key,
        secret,
        trial: (trial as boolean | undefined) ?? defaultTrial(url as string),
      } as AvEndpoint;
    });
  }
  const url = env["LIVEKIT_URL"];
  const key = env["LIVEKIT_API_KEY"];
  const secret = env["LIVEKIT_API_SECRET"];
  if (!url || !key || !secret) return [];
  return [{ id: "default", url, key, secret, trial: defaultTrial(url) }];
}

/// RoomServiceClient speaks HTTP; endpoints are configured as the ws(s) URL
/// clients dial.
export function httpHost(url: string): string {
  return url.replace(/^ws(s?):\/\//, "http$1://");
}

/// Which sources a member may publish. A `video` room always gets the camera;
/// a `voice` room gets it only while its video trial runs, and only on an
/// endpoint that allows trials. Returns the token lifetime too: a trial token
/// lives no longer than the trial, so a reconnect after it ends comes back
/// here and is minted without the camera.
export function cameraGrant(
  avLevel: string,
  trialEndsAt: string | null,
  endpoint: Pick<AvEndpoint, "trial">,
  now: Date,
  maxTtlSeconds: number,
): { camera: boolean; trial: boolean; ttlSeconds: number } {
  if (avLevel === "video") return { camera: true, trial: false, ttlSeconds: maxTtlSeconds };
  const left = trialEndsAt ? (new Date(trialEndsAt).getTime() - now.getTime()) / 1000 : 0;
  if (avLevel === "voice" && endpoint.trial && left > 0) {
    return { camera: true, trial: true, ttlSeconds: Math.max(1, Math.min(maxTtlSeconds, Math.ceil(left))) };
  }
  return { camera: false, trial: false, ttlSeconds: maxTtlSeconds };
}
