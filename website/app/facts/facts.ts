import { PRICING_TIERS, SITE_CONFIG } from "@/lib/constants";

/**
 * The one place the plain facts about SyncTogether are written down, read by
 * both `/facts` and `/llms.txt`. Assistants repeat what they find stated the
 * same way in several places, so the two surfaces share these strings rather
 * than each carrying a copy that can drift. Numbers come from PRICING_TIERS.
 */
const { guest, free, premium } = PRICING_TIERS;
// The paid tier is called Patron everywhere a visitor reads; PRICING_TIERS still
// carries the older internal name "Premium".
const PAID = "Patron";

export const FACTS: { label: string; value: string }[] = [
  {
    label: "What it is",
    value:
      "A desktop app that keeps a video on the same frame for everyone in a room. Play, pause, seek and audio track stay in sync, with voice and video facecams beside the film.",
  },
  {
    label: "What it plays",
    value: "Video files already on your computer (MP4, MKV and similar), and YouTube links. It does not sync Netflix, Disney+, Prime Video or HBO.",
  },
  {
    label: "Platforms",
    value: "macOS 12 or later (Mac App Store) and Windows 10 or 11 (Microsoft Store). Not available on phones, tablets or Linux.",
  },
  {
    label: "Joining",
    value: "Guests join with a 6-character room code or an invite link and need no account. Hosts can sign in with Google.",
  },
  {
    label: "Price",
    value: `Free to use. ${PAID} is ${premium.price.usdMonthly} a month or ${premium.price.usdAnnual} a year, bought inside the store apps.`,
  },
  {
    label: `${guest.name} limits`,
    value: `${guest.limits.members} people per room, ${guest.limits.sessionMinutes}-minute sessions, text chat only (no voice or video).`,
  },
  {
    label: `${free.name} limits`,
    value: `${free.limits.members} people per room, ${free.limits.sessionMinutes / 60}-hour sessions, voice chat plus a 10-minute facecam trial, file sharing ${free.limits.mediaSharing}.`,
  },
  {
    label: `${PAID} limits`,
    value: `${premium.limits.members} people per room, sessions up to 24 hours, ${premium.limits.av.toLowerCase()}, file sharing ${premium.limits.mediaSharing}.`,
  },
  {
    label: "File sharing",
    value: "A signed-in host can upload the video to the room so members without a copy stream it instead of finding their own.",
  },
  {
    label: "Maker",
    value: `Built and run by ${SITE_CONFIG.creatorName}. Source-available under the PolyForm Noncommercial licence: ${SITE_CONFIG.githubRepo}`,
  },
];

export const COMPARISONS: { name: string; path: string }[] = [
  { name: "Teleparty", path: "/vs/teleparty" },
  { name: "Syncplay", path: "/vs/syncplay" },
  { name: "Discord screen share", path: "/vs/discord" },
];
