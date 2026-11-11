"use client";

import { Analytics, type BeforeSendEvent } from "@vercel/analytics/next";
import { isUntrackedPath } from "@/lib/web-events";

/**
 * Vercel Web Analytics with the site's own tracking rules applied: OAuth return
 * pages and internal tools are not visits (counting them inflated visitors and
 * credited Google sign-in as a referrer), and invite codes in `/join/*` and
 * `/pair/*` are credentials, so they are masked before the URL leaves the browser.
 */
export function VercelAnalytics() {
  return <Analytics beforeSend={filterEvent} />;
}

function filterEvent(event: BeforeSendEvent): BeforeSendEvent | null {
  const url = new URL(event.url);
  if (isUntrackedPath(url.pathname)) return null;
  url.pathname = url.pathname.replace(/^\/(join|pair)\/[^/]+/, "/$1/*");
  return { ...event, url: url.toString() };
}
