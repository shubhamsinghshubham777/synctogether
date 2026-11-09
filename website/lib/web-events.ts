/**
 * The conversion moments the site reports beside its pageviews. An allow-list
 * rather than free text: the collector and the database check constraint
 * (`website_events_name_check`) carry the same names, so a typo cannot open a
 * new bucket and a hostile client cannot write arbitrary strings.
 */
export const WEB_EVENT_NAMES = [
  "join_handed_off",
  "join_fallback",
  "store_click_mac",
  "store_click_windows",
] as const;

export type WebEventName = (typeof WEB_EVENT_NAMES)[number];

export function isWebEventName(value: unknown): value is WebEventName {
  return typeof value === "string" && (WEB_EVENT_NAMES as readonly string[]).includes(value);
}

/**
 * The path an event is filed under. An invite code is a credential - for a live
 * room (`/join/ABC123`) or for pairing with someone (`/pair/ABC123`) - so both
 * are stored with the code replaced by `*`. Events never need it.
 */
export function eventPath(pathname: unknown): string {
  if (typeof pathname !== "string" || !pathname.startsWith("/")) return "/";
  const clean = pathname.split(/[?#]/)[0].slice(0, 255);
  return clean.replace(/^\/(join|pair)\/[^/]+/, "/$1/*");
}
