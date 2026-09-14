import { createAdminClient } from "./supabase/admin.ts";

export interface PublicStats {
  roomsAllTime: string;
  messagesSent: string;
  downloadsAllTime: string;
  publishable: boolean;
}

// Publishing a small number is worse than publishing none - these are the floors
// below which a figure reads as embarrassing rather than reassuring.
const FLOORS = {
  roomsAllTime: 2000,
  messagesSent: 20000,
  downloadsAllTime: 1000,
} as const;

// Round down to a friendly magnitude. An exact live-looking counter reads as
// broken the moment it stalls, so this never returns a precise figure.
function roundDown(n: number): string {
  const step = n < 1000 ? 100 : 1000;
  const rounded = Math.floor(n / step) * step;
  return `${rounded.toLocaleString("en-US")}+`;
}

export async function getPublicStats(): Promise<PublicStats> {
  const supabase = createAdminClient();

  const [rooms, messages, downloads] = await Promise.all([
    supabase.from("rooms").select("*", { count: "exact", head: true }),
    supabase.from("messages").select("*", { count: "exact", head: true }),
    supabase.from("website_downloads").select("*", { count: "exact", head: true }),
  ]);

  const roomsAllTime = rooms.count ?? 0;
  const messagesSent = messages.count ?? 0;
  const downloadsAllTime = downloads.count ?? 0;

  const publishable =
    roomsAllTime >= FLOORS.roomsAllTime &&
    messagesSent >= FLOORS.messagesSent &&
    downloadsAllTime >= FLOORS.downloadsAllTime;

  return {
    roomsAllTime: roundDown(roomsAllTime),
    messagesSent: roundDown(messagesSent),
    downloadsAllTime: roundDown(downloadsAllTime),
    publishable,
  };
}

export { FLOORS, roundDown };
