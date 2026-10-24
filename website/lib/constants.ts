export const SITE_CONFIG = {
  name: "SyncTogether",
  tagline: "Movie night, even when you're not in the same room.",
  description:
    "Watch movies together when you are apart. SyncTogether keeps your own video files and YouTube on the same frame for everyone, with voice and facecams beside the film. Free on Mac and Windows.",
  url: process.env.NEXT_PUBLIC_SITE_URL || "https://synctogether.app",
  supportEmail: "support@synctogether.app",
  githubRepo: "https://github.com/shubhamsinghshubham777/synctogether",
  microsoftStoreUrl: "https://apps.microsoft.com/detail/9P1BZTSXHDFS",
  appStoreUrl: "https://apps.apple.com/in/app/synctogether-watch-party/id6809185202?mt=12",
  creatorName: "Shubham Singh",
  creatorLinkedIn: "https://www.linkedin.com/in/shubhamsinghshubham777/",
};

/// Designated agent for copyright notices, as registered with the U.S.
/// Copyright Office. Cloud Media Sharing lets a host upload a video and stream
/// it to their room, which makes SyncTogether a host of user-uploaded content -
/// so the DMCA safe harbour, and the takedown process that earns it, has to be
/// real and published rather than implied.
///
/// The phone number on the registration is deliberately not repeated here: it
/// is already reachable through the public directory, and a personal mobile
/// number on a web page is scraped far more aggressively than one in a
/// government register.
export const DMCA_AGENT = {
  registrationNumber: "DMCA-1080733",
  serviceProvider: "Shubham Singh",
  agentName: "DMCA Agent, SyncTogether",
  email: "copyright@synctogether.app",
  address: [
    "House No. 1282, First Floor, Sector-9",
    "Bahadurgarh, Haryana 124507",
    "India",
  ],
  directoryUrl: "https://dmca.copyright.gov/osp/publish/history.html",
};

export type PatronCurrency = "USD" | "INR" | "PKR";
export type PatronPriceTable = Record<PatronCurrency, { monthly: number; annual: number }>;

/// Patron prices, in major units - the fallback figures. The pricing page
/// overlays Apple's live prices on these (lib/store-prices.ts) and shows these
/// when that call is unavailable. The stores are the source of truth: App Store
/// Connect and Partner Center each hold their own per-territory price, and the
/// two only offer slightly different steps (PKR 580 on Apple, 581 on Microsoft),
/// so change a tier there first, then here.
export const PATRON_PRICES: PatronPriceTable = {
  USD: { monthly: 3.99, annual: 29.99 },
  INR: { monthly: 199, annual: 999 },
  PKR: { monthly: 581, annual: 3000 },
};

/// Local-currency Patron prices shown beside the USD ones (USD stays the
/// headline). Territory names are display copy.
export const PATRON_LOCAL_PRICING: { country: string; currency: Exclude<PatronCurrency, "USD"> }[] = [
  { country: "India", currency: "INR" },
  { country: "Pakistan", currency: "PKR" },
];

/// Region -> Patron currency, from an ISO 3166-1 alpha-2 country code. Anything
/// not listed pays in USD (the store converts to the buyer's local currency).
export function currencyForCountry(country: string | null | undefined): PatronCurrency {
  switch (country?.toUpperCase()) {
    case "IN":
      return "INR";
    case "PK":
      return "PKR";
    default:
      return "USD";
  }
}

/// The visitor's country from request headers. The site is proxied by
/// Cloudflare, so Vercel only sees Cloudflare's edge IP and `x-vercel-ip-country`
/// names the edge, not the visitor; `cf-ipcountry` is the real one. The Vercel
/// header stays as the fallback for a host with no Cloudflare in front.
export function countryFromHeaders(headers: { get(name: string): string | null }): string | null {
  return headers.get("cf-ipcountry") || headers.get("x-vercel-ip-country");
}

/// "$3.99", "₹199", "PKR 581": no decimals unless the amount has them.
export function formatPatronPrice(currency: PatronCurrency, amount: number): string {
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency,
    currencyDisplay: currency === "PKR" ? "code" : "symbol",
    minimumFractionDigits: Number.isInteger(amount) ? 0 : 2,
    maximumFractionDigits: 2,
  })
    .format(amount)
    .replace(/\u00a0/g, " ");
}

export const PRICING_TIERS = {
  guest: {
    name: "Guest",
    badge: "No Account Needed",
    price: {
      usdMonthly: "$0",
      usdAnnual: "$0",
    },
    description: "Instant access for casual watching. Join with a 6-digit room code in seconds.",
    cta: "Download App",
    ctaLink: "/download",
    limits: {
      rooms: 1,
      members: 4,
      sessionMinutes: 60,
      totalSessionMinutes: 60,
      av: "None (text chat only)",
      reactions: "Standard (8 emoji)",
      dormantHours: 0,
      persistent: false,
      mediaSharing: "None (Local files only)",
    },
    features: [
      "1 active room at a time",
      "Up to 4 participants per room",
      "60-minute session duration",
      "Local files & YouTube sync",
      "Real-time chat & basic reactions",
      "No sign-up or credit card required",
    ],
  },
  free: {
    name: "Free",
    badge: "Most Popular",
    price: {
      usdMonthly: "$0",
      usdAnnual: "$0",
    },
    description: "Ideal for friend groups and watch parties with voice chat and extended sessions.",
    cta: "Get started free",
    ctaLink: "/download",
    limits: {
      rooms: 4,
      members: 8,
      sessionMinutes: 240,
      totalSessionMinutes: 240,
      av: "Voice only",
      reactions: "Standard (8 emoji)",
      dormantHours: 24,
      persistent: false,
      mediaSharing: "2.5 GB/week (up to 2.0 GB file)",
    },
    features: [
      "4 active rooms per host",
      "Up to 8 participants per room",
      "4-hour session duration",
      "2.5 GB weekly media streaming quota (up to 2.0 GB file)",
      "Low-latency Voice facecams",
      "Fast room creation & instant invites",
      "Syncs account across all your devices",
    ],
  },
  premium: {
    name: "Premium",
    badge: "Ultimate Experience",
    price: {
      usdMonthly: formatPatronPrice("USD", PATRON_PRICES.USD.monthly),
      usdAnnual: formatPatronPrice("USD", PATRON_PRICES.USD.annual),
      usdAnnualMonthlyEquivalent: formatPatronPrice("USD", Math.floor((PATRON_PRICES.USD.annual / 12) * 100) / 100),
      // No savingsPct here on purpose: PricingTable derives it from the two
      // amounts it displays (USD saves 37%), so it cannot drift from them.
    },
    description: "The complete theater experience. Video facecams, 16 members, 24h rooms, and persistent memory.",
    cta: "Upgrade to Premium",
    ctaLink: "/pricing",
    limits: {
      rooms: 20,
      members: 16,
      sessionMinutes: 240,
      totalSessionMinutes: 1440,
      av: "Voice + Video",
      reactions: "Extended (24 animated emoji)",
      dormantHours: 24,
      persistent: true,
      mediaSharing: "Unlimited (up to 10.0 GB file)",
    },
    features: [
      "20 persistent rooms with custom names",
      "Up to 16 participants per room",
      "Up to 24-hour continuous sessions",
      "Unlimited media streaming quota (up to 10.0 GB file)",
      "Video + Voice facecams",
      "24 animated Lottie reaction emoji",
      "Persistent rooms (never expire or delete)",
      "Public profile page at synctogether.app/u/yourhandle",
      "Extra streak freeze, so a busy week doesn't cost you",
      "Host's Premium perks shared with all room members",
      "Priority customer support",
    ],
  },
};

export const FAQ_ITEMS = [
  {
    category: "General",
    questions: [
      {
        q: "What is SyncTogether?",
        a: "An app for Mac and Windows that keeps a film on the same frame for everyone in a room. Play your own MP4 or MKV, or a YouTube link. Play, pause, seek and audio track stay in lockstep, and a machine that falls behind catches up by itself."
      },
      {
        q: "What platforms does SyncTogether support?",
        a: "SyncTogether runs on macOS (12.0+) and Windows (10 and 11). It is not available on phones, tablets or Linux yet. Install it from the Mac App Store or the Microsoft Store; both stores keep it up to date for you."
      },
      {
        q: "Do I need an account?",
        a: "No! You can use SyncTogether as a Guest without creating an account. Guests can create 60-minute rooms with up to 4 members. To get 4-hour rooms, voice chat, and cloud media sharing, simply sign in with a free account (Google, Apple, or Email)."
      },
      {
        q: "Is SyncTogether free?",
        a: "Yes! Both Guest and Free tiers are 100% free with no ads, and product analytics you can switch off. We offer a paid Premium tier for extended sessions, 16-member rooms, and video facecams."
      }
    ]
  },
  {
    category: "Rooms & sync",
    questions: [
      {
        q: "How do I create and join a room?",
        a: "Launch SyncTogether and click 'Create Room'. You will receive a unique 6-character room code (e.g. `X7K9P2`) and an invite link (`https://synctogether.app/join/X7K9P2`). Share it anywhere. The link opens the app for anyone who has it, and offers the download to anyone who does not, with the code kept for them."
      },
      {
        q: "What media formats are supported?",
        a: "SyncTogether supports all major local video containers and codecs (MP4, MKV, AVI, WEBM, MOV, etc.) along with direct YouTube video playback."
      },
      {
        q: "Does SyncTogether upload my video files?",
        a: "SyncTogether gives you two seamless options: (1) Local File Sync: If everyone already has the video file on their device, playback is 100% local and peer-synced with zero uploads. (2) Cloud Media Sharing: Room hosts can optionally upload and stream their video file directly to room guests (2.5 GB weekly quota / up to 2.0 GB per video on Free; unlimited uploads / up to 10.0 GB per video on Premium)."
      },
      {
        q: "What happens when a room expires?",
        a: "On Free and Guest tiers, rooms have a session timer (60 minutes for Guest, 4 hours for Free). Once a room expires, chat and temporary session data are automatically wiped. To keep permanent rooms that never expire, upgrade to Premium."
      }
    ]
  },
  {
    category: "Premium & billing",
    questions: [
      {
        q: "What do I get with SyncTogether Premium?",
        a: "Premium unlocks 20 persistent rooms, up to 16 participants per room, up to 24-hour sessions, crystal-clear Voice & Video facecams, 24 animated emoji reactions, persistent room memory, a claimable @handle with your own public profile page, and an extra streak freeze so a busy week doesn't break your run."
      },
      {
        q: "How do I subscribe?",
        a: "Open the SyncTogether app on Mac or Windows (Microsoft Store version), go to Premium and pick Monthly or Annual. The store handles payment, tax and renewal. Premium belongs to your account, so it unlocks on every device you sign in on, Windows included."
      },
      {
        q: "Can I cancel anytime?",
        a: "Yes. Cancel in your App Store or Microsoft account subscription settings at any time. Your Premium benefits stay active until the end of the period you already paid for."
      },
      {
        q: "What is your refund policy?",
        a: "Refunds are handled by the store you bought from, through its own refund process (for Apple, reportaproblem.apple.com). If something went wrong with your Premium access, email support@synctogether.app and we will help."
      },
      {
        q: "I subscribed on my Mac but my Windows app still shows Free. What should I do?",
        a: "Make sure you are signed in with the same SyncTogether account on both devices. Premium updates within seconds. If it does not appear, restart the app or open the Premium screen and tap Refresh status."
      }
    ]
  },
  {
    category: "Privacy & security",
    questions: [
      {
        q: "What data does SyncTogether collect?",
        a: "We collect your Google profile (email and display name) for authentication, or assign an anonymous ID for guests. In Local Sync mode, your full disk paths and video files never leave your device (only the basic filename and duration are synced for alignment). In Cloud Media Sharing mode, uploaded files are encrypted and purged when the room ends. Chat messages and reactions are automatically wiped when rooms close."
      },
      {
        q: "What are streaks, badges and the leaderboard?",
        a: "SyncTogether counts the time you spend watching with other people. Twenty minutes in a room with somebody makes the day count towards your streak, and badges unlock along the way. Points are one a minute watched together (capped daily), plus a bonus for each different person you watch with, multiplied by your streak, so watching 40 minutes every day beats twelve hours on one Saturday. Watching alone earns nothing, and neither does a room left open, because the point is time spent together. Guests do not collect streaks: guest accounts are wiped after a few days, so a streak held on one would not survive the week."
      },
      {
        q: "Does the leaderboard show my name to strangers?",
        a: "Only if you turn it on. Leaderboards and public profile pages are opt-in from Profile in the desktop app, and turning it on publishes your display name, avatar, streak, rank and badges, and nothing about what you watched, who you watched it with, or anything you typed. Turning it off removes you immediately. You can see your own rank privately either way."
      },
      {
        q: "What is in a shared recap, and who can see it?",
        a: "A recap is a page you can post anywhere: how long the session ran, how many reactions and messages there were, and a few silly awards. It never includes what you watched: no file names, no links, no chat. Anyone else in the room who has not turned on a public profile appears as an anonymous avatar with no name. Recap links are unguessable, hidden from search engines, and expire after 90 days."
      },
      {
        q: "Does Premium buy a better leaderboard position?",
        a: "No, and it never will. Premium gets an extra streak freeze (so a busy week costs you less), exclusive avatar frames, and a claimable @handle with its own public profile page, but not a single extra point. Appearing on a board and ranking on it are both free. A board you can buy your way up is not worth climbing."
      },
      {
        q: "Can I opt out of analytics?",
        a: "Yes. In the desktop app under Profile → 'Share usage data', you can toggle anonymous product analytics off at any time. Crash and diagnostic reporting carries no personal data."
      },
      {
        q: "Are voice and video facecams recorded?",
        a: "Never. Voice and video streams are transmitted end-to-end via encrypted real-time relays and are never recorded or stored on any server."
      }
    ]
  }
];
