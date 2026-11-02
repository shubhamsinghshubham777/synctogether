import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { eventPath, isWebEventName } from "@/lib/web-events";

export async function POST(request: Request) {
  try {
    const body = await request.json().catch(() => ({}));
    const { visitorId, pathname, referrer, event } = body;

    if (!visitorId || typeof visitorId !== "string" || visitorId.length > 128) {
      return NextResponse.json({ error: "Invalid visitor ID" }, { status: 400 });
    }

    // A conversion event rather than a pageview: the visitor row already exists
    // (the pageview beacon ran first), so this only files the event. An unknown
    // visitor fails the foreign key and is dropped - an event with no landing
    // has nothing to be a conversion of.
    if (event !== undefined) {
      if (!isWebEventName(event)) {
        return NextResponse.json({ error: "Unknown event" }, { status: 400 });
      }
      const { error } = await createAdminClient()
        .from("website_events")
        .insert({ visitor_id: visitorId, name: event, path: eventPath(pathname) });
      if (error) console.warn("Analytics event warning:", error.message);
      return NextResponse.json({ ok: true });
    }

    const userAgent = request.headers.get("user-agent") || undefined;
    // An invite code is a live room's join credential, so `/join/ABC123` is
    // filed as `/join/*` here exactly as it is for events.
    const cleanPath = eventPath(pathname);
    const cleanRef = typeof referrer === "string" ? referrer.slice(0, 500) : null;

    const supabase = createAdminClient();

    // 1. Fetch existing visitor if present
    const { data: existingVisitor, error: fetchErr } = await supabase
      .from("website_visitors")
      .select("visitor_id, pageviews_count")
      .eq("visitor_id", visitorId)
      .maybeSingle();

    if (fetchErr) {
      console.warn("Analytics fetch visitor warning:", fetchErr.message);
    }

    if (!existingVisitor) {
      // New unique visitor
      await supabase.from("website_visitors").insert({
        visitor_id: visitorId,
        first_seen_at: new Date().toISOString(),
        last_seen_at: new Date().toISOString(),
        pageviews_count: 1,
        first_referrer: cleanRef,
        first_path: cleanPath,
        user_agent: userAgent,
      });
    } else {
      // Existing returning visitor
      await supabase
        .from("website_visitors")
        .update({
          last_seen_at: new Date().toISOString(),
          pageviews_count: (existingVisitor.pageviews_count || 1) + 1,
        })
        .eq("visitor_id", visitorId);
    }

    // 2. Insert pageview record
    await supabase.from("website_pageviews").insert({
      visitor_id: visitorId,
      pathname: cleanPath,
      referrer: cleanRef,
    });

    return NextResponse.json({ ok: true });
  } catch (err) {
    console.error("Analytics collection error:", err);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
