import type { Metadata } from "next";
import { LegalShell, LegalNum, LegalPledge } from "@/components/LegalShell";
import { SITE_CONFIG } from "@/lib/constants";
import {
  EyeOff,
  Trash2,
  Download,
  Video,
  Mic,
  Play,
  ExternalLink,
} from "lucide-react";

const TOC = [
  { id: "s-1", n: "01", label: "Scope & Services Covered" },
  { id: "s-2", n: "02", label: "Information We Collect & How We Process It" },
  { id: "s-3", n: "03", label: "What We Explicitly DO NOT Collect or Do" },
  { id: "s-4", n: "04", label: "Media Playback Architecture & YouTube Disclosures" },
  { id: "s-5", n: "05", label: "Hardware Permissions & System Access" },
  { id: "s-5b", n: "5b", label: "Streaks, Badges, Leaderboards & Shared Recaps" },
  { id: "s-6", n: "06", label: "Legal Bases for Processing (GDPR / UK GDPR)" },
  { id: "s-7", n: "07", label: "Authorized Third-Party Subprocessors" },
  { id: "s-8", n: "08", label: "Data Retention & Automatic Purge Schedules" },
  { id: "s-9", n: "09", label: "Cookies & Local Client Storage" },
  { id: "s-10", n: "10", label: "Your Privacy Rights (GDPR, CCPA/CPRA, DPDP)" },
  { id: "s-11", n: "11", label: "Children’s Privacy (COPPA & Global Protections)" },
  { id: "s-12", n: "12", label: "Data Security & Encryption" },
  { id: "s-13", n: "13", label: "Changes to This Privacy Policy" },
  { id: "s-14", n: "14", label: "Contact Us & Grievance Redressal" },
];

export const metadata: Metadata = {
  title: "Privacy Policy: Complete Data Protection & Security",
  description:
    "Learn how SyncTogether protects your personal data, media privacy, real-time voice and video streams, and payment information.",
};

export default function PrivacyPage() {
  const lastUpdated = "August 30, 2026";
  const effectiveDate = "August 30, 2026";

  const subprocessors = [
    {
      name: "Supabase, Inc.",
      purpose: "Authentication, user profiles, PostgreSQL cloud database with Row Level Security, private real-time synchronization channels, and serverless Edge Functions.",
      location: "United States / Global AWS",
      privacyUrl: "https://supabase.com/privacy",
    },
    {
      name: "Cloudflare, Inc.",
      purpose: "Cloudflare Turnstile bot detection for guest signups, Cloudflare R2 Object Storage for temporary Cloud Media Sharing, DNS, and DDoS protection.",
      location: "United States / Global Edge",
      privacyUrl: "https://www.cloudflare.com/privacypolicy/",
    },
    {
      name: "LiveKit, Inc. (LiveKit Cloud)",
      purpose: "Encrypted WebRTC real-time Selective Forwarding Unit (SFU) media relay for voice chat and video facecams.",
      location: "United States / Global Relays",
      privacyUrl: "https://livekit.com/legal/privacy-policy",
    },
    {
      name: "Paddle Payments Ltd / Paddle.com",
      purpose: "Authorized Merchant of Record (MoR) handling payment processing, billing subscriptions, invoices, and sales tax / VAT compliance.",
      location: "United Kingdom / United States",
      privacyUrl: "https://www.paddle.com/legal/privacy",
    },
    {
      name: "Functional Software, Inc. (Sentry)",
      purpose: "Application stability monitoring, crash reporting, and diagnostics telemetry (error stack traces and OS versions).",
      location: "United States",
      privacyUrl: "https://sentry.io/privacy/",
    },
    {
      name: "PostHog, Inc.",
      purpose: "Privacy-conscious product analytics and feature engagement tracking (with full client-side opt-out support).",
      location: "United States / European Union",
      privacyUrl: "https://posthog.com/privacy",
    },
    {
      name: "Vercel, Inc.",
      purpose: "Marketing website and account portal hosting, edge middleware routing, and privacy-friendly web traffic analytics.",
      location: "United States / Global Edge",
      privacyUrl: "https://vercel.com/legal/privacy-policy",
    },
    {
      name: "Apple Inc.",
      purpose: "Sign in with Apple single sign-on authentication.",
      location: "United States / Global",
      privacyUrl: "https://www.apple.com/legal/privacy/",
    },
    {
      name: "Google LLC",
      purpose: "Google OAuth 2.0 single sign-on authentication and YouTube IFrame video player embeds.",
      location: "United States / Global",
      privacyUrl: "https://policies.google.com/privacy",
    },
  ];

  return (
    <LegalShell
      current="/privacy"
      kicker="Data protection"
      title="Privacy Policy"
      dek="What the booth sees, what it keeps, and for how long. Your film never leaves your machine; most of the rest is gone when the house lights come up."
      toc={TOC}
      dates={[{ label: "Effective", value: effectiveDate }, { label: "Updated", value: lastUpdated }]}
    >
        {/* Core Privacy Pledge */}
        <section className="space-y-3">
          <LegalPledge title="Our Privacy Pledge">
            <p>
              SyncTogether is designed around privacy by architecture. When synchronizing local files, your video bytes and absolute disk paths never leave your device. When using real-time facecams and voice chat, streams are end-to-end encrypted in transit and <strong>never recorded or stored</strong> on any server. We do not sell your personal data, and we do not track you across the web.
            </p>
          </LegalPledge>
        </section>

        {/* 1. Scope & Applicability */}
        <section id="s-1" className="space-y-4">
          <h2>
            <LegalNum n="1" />
            Scope &amp; Services Covered
          </h2>
          <p className="text-gray-300">
            This Privacy Policy governs your use of the <strong>SyncTogether</strong> platform, including:
          </p>
          <ul className="space-y-2 text-gray-400 list-disc list-inside">
            <li>
              The SyncTogether desktop client applications (macOS and Windows).
            </li>
            <li>
              The official website, documentation, and subscription management portal located at{" "}
              <a href="https://synctogether.app" className="text-purple-300 underline hover:text-white">
                https://synctogether.app
              </a>.
            </li>
            <li>
              Our cloud infrastructure, authentication bridges, real-time synchronization channels, media sharing services, and serverless edge functions.
            </li>
          </ul>
        </section>

        {/* 2. Information We Collect */}
        <section id="s-2" className="space-y-4">
          <h2>
            <LegalNum n="2" />
            Information We Collect &amp; How We Process It
          </h2>
          <div className="space-y-4 text-gray-300">
            <div className="p-5 rounded-xl bg-white/[0.02] border border-white/5 space-y-2.5">
              <strong className="text-white text-base block">A. Account &amp; Identity Data</strong>
              <ul className="space-y-1.5 text-gray-400 list-disc list-inside">
                <li>
                  <strong className="text-gray-200">Account Authentication (Google, Apple, or Email):</strong> When you sign in using Google OAuth or Sign in with Apple, we receive and store your email address and display name/avatar if provided. When you sign in using email OTP, we store your email address and generate a secure passwordless login token.
                </li>
                <li>
                  <strong className="text-gray-200">Guest Authentication:</strong> If you use SyncTogether as a Guest without an account, we generate a temporary random anonymous identifier (e.g. <code>Guest-a1b2</code>). Guest sessions use Cloudflare Turnstile tokens to verify human interaction and prevent automated abuse.
                </li>
                <li>
                  <strong className="text-gray-200">User Profiles:</strong> You may customize your public display name at any time in your profile settings.
                </li>
              </ul>
            </div>

            <div className="p-5 rounded-xl bg-white/[0.02] border border-white/5 space-y-2.5">
              <strong className="text-white text-base block">B. Media Playback &amp; Synchronization Metadata</strong>
              <ul className="space-y-1.5 text-gray-400 list-disc list-inside">
                <li>
                  <strong className="text-gray-200">Local File Sync Mode:</strong> When syncing local video files, we process only the file&apos;s basic filename (basename, e.g. <code>movie.mp4</code>), duration, and playback timestamps (position, play, pause, seek) over private real-time channels. <em>Your absolute disk directory structure and raw video bytes remain on your local disk.</em>
                </li>
                <li>
                  <strong className="text-gray-200">Cloud Media Sharing Mode (Optional Host Upload):</strong> When a host chooses to stream a file directly to room participants via Cloud Media Sharing, the video file is encrypted in transit and uploaded temporarily to our Cloudflare R2 object storage. We store file size and chunk metadata to generate time-limited, presigned download URLs for authenticated room members.
                </li>
                <li>
                  <strong className="text-gray-200">YouTube Sync Mode:</strong> When synchronizing YouTube playback, we process the canonical YouTube Video ID, playback state, and timestamp coordinates.
                </li>
              </ul>
            </div>

            <div className="p-5 rounded-xl bg-white/[0.02] border border-white/5 space-y-2.5">
              <strong className="text-white text-base block">C. Real-time Communication (Voice, Video &amp; Chat)</strong>
              <ul className="space-y-1.5 text-gray-400 list-disc list-inside">
                <li>
                  <strong className="text-gray-200">Voice &amp; Video Facecams:</strong> Live audio and video streams are transmitted in real-time over encrypted WebRTC connections via LiveKit Cloud. <strong>Voice and video streams are NEVER recorded, monitored, transcribed, or stored on our servers.</strong>
                </li>
                <li>
                  <strong className="text-gray-200">Room Chat &amp; Reactions:</strong> Text chat messages and emoji/Lottie reaction triggers are broadcast to room participants. In-room messages are temporary and tied strictly to the active room lifecycle.
                </li>
              </ul>
            </div>

            <div className="p-5 rounded-xl bg-white/[0.02] border border-white/5 space-y-2.5">
              <strong className="text-white text-base block">D. Payment &amp; Subscription Information</strong>
              <p className="text-gray-400">
                Premium subscription payments are processed directly by our authorized Merchant of Record, <strong>Paddle Payments Ltd / Paddle.com</strong>. Paddle handles all credit card, debit card, PayPal, Apple Pay, Google Pay, and UPI transactions.
              </p>
              <p className="text-gray-400">
                <strong>SyncTogether never sees, processes, or stores your credit card numbers, CVVs, or bank account details.</strong> We receive only billing status confirmations, subscription tier flags, transaction IDs, and renewal timestamps from Paddle via verified webhooks.
              </p>
            </div>

            <div className="p-5 rounded-xl bg-white/[0.02] border border-white/5 space-y-2.5">
              <strong className="text-white text-base block">E. Diagnostics, Crash Reports &amp; Analytics</strong>
              <ul className="space-y-1.5 text-gray-400 list-disc list-inside">
                <li>
                  <strong className="text-gray-200">Crash Reporting (Sentry):</strong> If an unexpected application failure occurs, Sentry captures stack traces, operating system version, app version, and breadcrumb execution context to assist our engineering team in resolving bugs.
                </li>
                <li>
                  <strong className="text-gray-200">Product Analytics (PostHog):</strong> We collect aggregated feature engagement metrics (e.g. room creation, sync latency, upgrade flows). <strong>You can opt out of analytics at any time</strong> with a single toggle in the desktop app under <em>Profile &rarr; &ldquo;Share usage data&rdquo;</em>. Opting out immediately stops all analytics event collection.
                </li>
                <li>
                  <strong className="text-gray-200">Web Analytics (Vercel Analytics):</strong> Our marketing website uses privacy-friendly Vercel Analytics to measure page view volume without tracking individual users or using invasive cookies.
                </li>
              </ul>
            </div>
          </div>
        </section>

        {/* 3. What We DO NOT Collect */}
        <section id="s-3" className="space-y-4">
          <h2>
            <LegalNum n="3" />
            What We Explicitly DO NOT Collect or Do
          </h2>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 text-sm sm:text-base">
            <div className="p-4 sm:p-5 rounded-xl bg-red-500/5 border border-red-500/10 text-gray-300 space-y-1">
              <strong className="text-red-300 block mb-1 font-semibold">No Data Selling or Sharing</strong>
              We never sell, rent, monetize, or trade your personal data to advertisers, data brokers, or third parties.
            </div>
            <div className="p-4 sm:p-5 rounded-xl bg-red-500/5 border border-red-500/10 text-gray-300 space-y-1">
              <strong className="text-red-300 block mb-1 font-semibold">No Audio/Video Recordings</strong>
              We never record, listen to, store, or create transcripts of your live voice chat or video facecams.
            </div>
            <div className="p-4 sm:p-5 rounded-xl bg-red-500/5 border border-red-500/10 text-gray-300 space-y-1">
              <strong className="text-red-300 block mb-1 font-semibold">No Unselected File Scanning</strong>
              We never scan, index, read, or upload files, folders, or documents outside of the media file you deliberately select.
            </div>
            <div className="p-4 sm:p-5 rounded-xl bg-red-500/5 border border-red-500/10 text-gray-300 space-y-1">
              <strong className="text-red-300 block mb-1 font-semibold">No Cross-Site Tracking</strong>
              We do not use advertising tracking pixels, fingerprinting scripts, or cross-site behavioral trackers.
            </div>
          </div>
        </section>

        {/* 4. Media Architecture: Local vs Cloud vs YouTube */}
        <section id="s-4" className="space-y-4">
          <h2>
            <LegalNum n="4" />
            Media Playback Architecture &amp; YouTube Disclosures
          </h2>
          <div className="space-y-3.5 text-gray-300">
            <p>
              SyncTogether offers flexible media options with distinct privacy boundaries:
            </p>
            <div className="space-y-3">
              <div className="p-4 sm:p-5 rounded-xl bg-white/[0.02] border border-white/5 space-y-1.5">
                <strong className="text-white block font-semibold text-base">1. Local File Sync Mode (Peer Synchronization)</strong>
                <p className="text-gray-400">
                  When all room participants have their own copy of a video file on their device, SyncTogether coordinates playback strictly via lightweight control messages (play/pause/seek). <strong>Zero video bytes are transmitted to any server or other user.</strong>
                </p>
              </div>
              <div className="p-4 sm:p-5 rounded-xl bg-white/[0.02] border border-white/5 space-y-1.5">
                <strong className="text-white block font-semibold text-base">2. Cloud Media Sharing Mode (Encrypted Cloudflare R2 Storage)</strong>
                <p className="text-gray-400">
                  When a host uploads a video file to stream to participants, the file is uploaded to an isolated, encrypted Cloudflare R2 storage bucket. Access is granted solely to authenticated room participants via time-limited, signed URLs. <strong>Shared media is strictly ephemeral and is automatically and permanently deleted upon room closure or expiration.</strong>
                </p>
              </div>
              <div className="p-4 sm:p-5 rounded-xl bg-white/[0.02] border border-white/5 space-y-2">
                <div className="flex items-center gap-2 font-semibold text-white text-base">
                  <Play className="w-4 h-4 text-red-500 fill-red-500 shrink-0" />
                  <span>3. YouTube API Services &amp; Embed Terms</span>
                </div>
                <p className="text-gray-400">
                  SyncTogether enables synchronized playback of public YouTube videos using the official YouTube IFrame API (via privacy-enhanced mode <code>youtube-nocookie.com</code>). By using YouTube playback in SyncTogether, you agree to be bound by the YouTube Terms of Service and acknowledge Google&apos;s Privacy Policy.
                </p>
                <div className="flex flex-wrap items-center gap-3 pt-1 text-purple-300 text-sm">
                  <a
                    href="https://www.youtube.com/t/terms"
                    target="_blank"
                    rel="noopener noreferrer"
                    className="inline-flex items-center gap-1 hover:text-white underline"
                  >
                    <span>YouTube Terms of Service</span>
                    <ExternalLink className="w-3.5 h-3.5" />
                  </a>
                  <span>&bull;</span>
                  <a
                    href="https://policies.google.com/privacy"
                    target="_blank"
                    rel="noopener noreferrer"
                    className="inline-flex items-center gap-1 hover:text-white underline"
                  >
                    <span>Google Privacy Policy</span>
                    <ExternalLink className="w-3.5 h-3.5" />
                  </a>
                </div>
              </div>
            </div>
          </div>
        </section>

        {/* 5. Device Permissions */}
        <section id="s-5" className="space-y-4">
          <h2>
            <LegalNum n="5" />
            Hardware Permissions &amp; System Access
          </h2>
          <p className="text-gray-300">
            The SyncTogether desktop app requests the following operating system permissions strictly on an as-needed basis:
          </p>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div className="p-4 sm:p-5 rounded-xl bg-white/[0.02] border border-white/5 space-y-1.5">
              <div className="flex items-center gap-2 text-white font-semibold text-base">
                <Mic className="w-4 h-4 text-purple-400" />
                <span>Microphone Access</span>
              </div>
              <p className="text-gray-400">
                Used solely to transmit your audio when voice chat is explicitly unmuted by you in an active room.
              </p>
            </div>
            <div className="p-4 sm:p-5 rounded-xl bg-white/[0.02] border border-white/5 space-y-1.5">
              <div className="flex items-center gap-2 text-white font-semibold text-base">
                <Video className="w-4 h-4 text-purple-400" />
                <span>Camera Access</span>
              </div>
              <p className="text-gray-400">
                Used solely to capture and stream your video facecam when video is explicitly enabled by you in a room.
              </p>
            </div>
          </div>
        </section>

        {/* 5b. Streaks, badges and leaderboards */}
        <section id="s-5b" className="space-y-4">
          <h2>
            <LegalNum n="5b" />
            Streaks, Badges, Leaderboards &amp; Shared Recaps
          </h2>
          <p className="text-gray-300">
            SyncTogether records how much time you spend watching <em>with other people</em>,
            so it can show you a streak, award badges and rank you on a leaderboard.
            This is the only part of the product that can publish anything about you,
            and it is off until you turn it on.
          </p>
          <div className="space-y-3 text-gray-400">
            <p>
              <span className="text-white font-semibold">What is recorded.</span> Minutes
              credited per day, which rooms they were in, which accounts you shared those
              rooms with, and the badges you have crossed. We never record what you
              watched: no file names, no file paths, no YouTube links or video IDs, and
              no chat content. Guest sessions record nothing at all.
            </p>
            <p>
              <span className="text-white font-semibold">What becomes public, and only
              if you say so.</span> Leaderboards and public profile pages are strictly
              opt-in, from Profile in the desktop app. Turning it on publishes your
              display name, avatar, current streak, rank and badges. Turning it off
              removes you from every board and hides your profile page immediately. Your
              own rank stays visible privately either way, so the choice is an informed
              one rather than a blind one.
            </p>
            <p>
              <span className="text-white font-semibold">Shared recaps.</span> When a
              session ends you may share a recap page. It carries session counts (minutes,
              reactions, messages) and the people who were there, but anyone in that room
              who has not opted into a public profile appears as an anonymous avatar with
              no name. Recap URLs are unguessable, excluded from search engines, and
              deleted automatically after 90 days.
            </p>
            <p>
              <span className="text-white font-semibold">Public pages carry no account
              identifiers.</span> Avatars on shared pages are keyed to a one-way hash, not
              to your user ID.
            </p>
            <p>
              <span className="text-white font-semibold">One switch, not two.</span>{" "}
              Turning off &ldquo;Share usage data&rdquo; in the desktop app stops product
              analytics <em>and</em> the watch records that streaks, badges and
              leaderboards are built from. They are the same records, so one switch
              governs both. A control that quietly left half of it running would not be
              much of a control. The app says so on the switch itself, and lists every
              single event it would otherwise send.
            </p>
            <p>
              <span className="text-white font-semibold">Deletion.</span> Deleting your
              account removes your ledger, streak, badges, co-watch history and every
              recap you created, along with everything else described in this policy. You
              can also delete any individual shared recap at any time, from Profile in the
              app, and the link stops working for everyone immediately.
            </p>
          </div>
        </section>

        {/* 6. Legal Bases for Processing (GDPR) */}
        <section id="s-6" className="space-y-4">
          <h2>
            <LegalNum n="6" />
            Legal Bases for Processing (GDPR / UK GDPR)
          </h2>
          <div className="space-y-2 text-gray-400">
            <p className="text-gray-300">
              Under European data protection laws (GDPR / UK GDPR), we process personal data under the following lawful bases:
            </p>
            <ul className="space-y-2 list-disc list-inside">
              <li>
                <strong className="text-gray-200">Contractual Necessity (Art. 6(1)(b) GDPR):</strong> To authenticate your account, maintain room synchronization, manage subscriptions, and deliver the services you requested.
              </li>
              <li>
                <strong className="text-gray-200">Legitimate Interests (Art. 6(1)(f) GDPR):</strong> To detect bot abuse via Turnstile, troubleshoot software crashes via Sentry, and safeguard platform security.
              </li>
              <li>
                <strong className="text-gray-200">Consent (Art. 6(1)(a) GDPR):</strong> For optional product analytics via PostHog (which can be toggled off at any time).
              </li>
              <li>
                <strong className="text-gray-200">Legal Obligation (Art. 6(1)(c) GDPR):</strong> To comply with applicable tax, financial, and regulatory requirements via our Merchant of Record.
              </li>
            </ul>
          </div>
        </section>

        {/* 7. Subprocessors Table */}
        <section id="s-7" className="space-y-4">
          <h2>
            <LegalNum n="7" />
            Authorized Third-Party Subprocessors
          </h2>
          <p className="text-gray-300">
            We partner with industry-standard, privacy-compliant infrastructure providers to securely operate SyncTogether. All subprocessors are bound by data protection agreements:
          </p>
          <div className="overflow-x-auto rounded-xl border border-white/10 bg-white/[0.01]">
            <table className="w-full text-left text-xs sm:text-sm text-gray-300">
              <thead className="bg-white/5 text-white font-mono uppercase text-xs border-b border-white/10">
                <tr>
                  <th className="p-3.5">Subprocessor</th>
                  <th className="p-3.5">Purpose &amp; Service</th>
                  <th className="p-3.5">Location</th>
                  <th className="p-3.5 [overflow-wrap:normal]">Privacy Link</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-white/5 text-gray-400">
                {subprocessors.map((p) => (
                  <tr key={p.name} className="hover:bg-white/[0.02] transition-colors">
                    <td className="p-3.5 font-semibold text-white whitespace-nowrap">{p.name}</td>
                    <td className="p-3.5 leading-normal">{p.purpose}</td>
                    <td className="p-3.5 whitespace-nowrap">{p.location}</td>
                    <td className="p-3.5 whitespace-nowrap">
                      <a
                        href={p.privacyUrl}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="text-purple-300 hover:text-white underline inline-flex items-center gap-1"
                      >
                        <span>Policy</span>
                        <ExternalLink className="w-3.5 h-3.5" />
                      </a>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>

        {/* 8. Data Retention & Automatic Purge */}
        <section id="s-8" className="space-y-4">
          <h2>
            <LegalNum n="8" />
            Data Retention &amp; Automatic Purge Schedules
          </h2>
          <div className="space-y-3 text-gray-300">
            <p>
              We enforce strict automated data lifecycles to minimize data footprint:
            </p>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div className="p-4 sm:p-5 rounded-xl bg-white/[0.02] border border-white/5 space-y-1.5">
                <strong className="text-white block font-semibold text-base">Room Chat &amp; Reactions</strong>
                <p className="text-gray-400">
                  Cascade-deleted permanently from the database immediately when a room is ended by the host or reaches its expiration time.
                </p>
              </div>
              <div className="p-4 sm:p-5 rounded-xl bg-white/[0.02] border border-white/5 space-y-1.5">
                <strong className="text-white block font-semibold text-base">Cloud Media Sharing (R2)</strong>
                <p className="text-gray-400">
                  Media files in R2 storage are purged automatically via database triggers and recurring automated sweeps whenever a room is closed or expires.
                </p>
              </div>
              <div className="p-4 sm:p-5 rounded-xl bg-white/[0.02] border border-white/5 space-y-1.5">
                <strong className="text-white block font-semibold text-base">Guest Accounts</strong>
                <p className="text-gray-400">
                  Anonymous guest profiles inactive for more than 3 days without active rooms are purged daily via automated database routines.
                </p>
              </div>
              <div className="p-4 sm:p-5 rounded-xl bg-white/[0.02] border border-white/5 space-y-1.5">
                <strong className="text-white block font-semibold text-base">Billing &amp; Tax Records</strong>
                <p className="text-gray-400">
                  Retained by Paddle Payments Ltd in accordance with statutory financial, tax, and accounting compliance requirements (typically 5 to 7 years).
                </p>
              </div>
            </div>
          </div>
        </section>

        {/* 9. Cookies & Local Storage */}
        <section id="s-9" className="space-y-4">
          <h2>
            <LegalNum n="9" />
            Cookies &amp; Local Client Storage
          </h2>
          <div className="space-y-2 text-gray-300">
            <p>
              SyncTogether minimizes cookie and local storage usage:
            </p>
            <ul className="space-y-2 text-gray-400 list-disc list-inside">
              <li>
                <strong className="text-gray-200">Strictly Essential Website Cookies:</strong> We use secure, HTTP-only authentication session cookies (<code>sb-*-auth-token</code>) to keep you signed in to your account portal.
              </li>
              <li>
                <strong className="text-gray-200">Desktop Client Local Storage:</strong> The desktop app uses local storage (such as <code>SharedPreferences</code> and secure keychain tokens) to remember your login session, UI theme, volume preferences, and your analytics opt-out preference.
              </li>
              <li>
                <strong className="text-gray-200">No Advertising Cookies:</strong> We do not use third-party advertising, retargeting, or cross-site tracking cookies.
              </li>
            </ul>
          </div>
        </section>

        {/* 10. Your Privacy Rights */}
        <section id="s-10" className="space-y-4">
          <h2>
            <LegalNum n="10" />
            Your Privacy Rights (GDPR, CCPA/CPRA, DPDP)
          </h2>
          <div className="space-y-4 text-gray-300">
            <p>
              Regardless of your geographic location, SyncTogether provides full control over your personal data:
            </p>
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
              <div className="p-4 sm:p-5 rounded-xl bg-purple-500/5 border border-purple-500/15 space-y-2">
                <div className="flex items-center gap-2 font-semibold text-white text-base">
                  <Download className="w-4 h-4 text-purple-400" />
                  <span>Export Data</span>
                </div>
                <p className="text-gray-400 text-sm">
                  Export a complete JSON archive of your user profile, entitlement level, and subscription records anytime from your Account dashboard.
                </p>
              </div>

              <div className="p-4 sm:p-5 rounded-xl bg-purple-500/5 border border-purple-500/15 space-y-2">
                <div className="flex items-center gap-2 font-semibold text-white text-base">
                  <Trash2 className="w-4 h-4 text-red-400" />
                  <span>Delete Account</span>
                </div>
                <p className="text-gray-400 text-sm">
                  Permanently erase your account, profile, rooms, and all associated database records directly in the desktop app or website.
                </p>
              </div>

              <div className="p-4 sm:p-5 rounded-xl bg-purple-500/5 border border-purple-500/15 space-y-2">
                <div className="flex items-center gap-2 font-semibold text-white text-base">
                  <EyeOff className="w-4 h-4 text-amber-400" />
                  <span>Opt Out of Analytics</span>
                </div>
                <p className="text-gray-400 text-sm">
                  Toggle off product analytics telemetry with one click in the app profile. When disabled, zero usage events are queued or transmitted.
                </p>
              </div>
            </div>

            <div className="p-5 rounded-xl bg-white/[0.02] border border-white/5 space-y-3 text-gray-400">
              <strong className="text-white block text-base">California Residents (CCPA / CPRA):</strong>
              <p>
                We do not sell personal information or share it for cross-context behavioral advertising. You have the right to know what personal information is collected, request deletion, request correction, and not be discriminated against for exercising your privacy rights.
              </p>
              <strong className="text-white block text-base pt-1">India Residents (DPDP Act 2023):</strong>
              <p>
                In accordance with the Digital Personal Data Protection Act, 2023, you have the right to access summary information, seek correction or erasure, nominate representatives, and access our grievance redressal mechanism.
              </p>
            </div>
          </div>
        </section>

        {/* 11. Children's Privacy */}
        <section id="s-11" className="space-y-4">
          <h2>
            <LegalNum n="11" />
            Children&apos;s Privacy (COPPA &amp; Global Protections)
          </h2>
          <p className="text-gray-300">
            SyncTogether is not directed to children under the age of 13 (or under 16 in the European Union / UK). We do not knowingly collect personal information from children. If you believe a child has provided us with personal data without parental consent, please contact us immediately at{" "}
            <a href={`mailto:${SITE_CONFIG.supportEmail}`} className="text-purple-300 hover:text-white underline">
              {SITE_CONFIG.supportEmail}
            </a>{" "}
            and we will promptly delete the data.
          </p>
        </section>

        {/* 12. Security Measures */}
        <section id="s-12" className="space-y-4">
          <h2>
            <LegalNum n="12" />
            Data Security &amp; Encryption
          </h2>
          <div className="space-y-2 text-gray-400">
            <p className="text-gray-300">
              We implement comprehensive technical and organizational safeguards to protect your data:
            </p>
            <ul className="space-y-2 list-disc list-inside">
              <li><strong>Encryption in Transit:</strong> All network communication is enforced over TLS 1.3 encryption. Real-time audio and video streams use DTLS/SRTP WebRTC protocols.</li>
              <li><strong>Database Protection:</strong> PostgreSQL database security is enforced via strict Row Level Security (RLS) policies ensuring users can only access their authorized data.</li>
              <li><strong>Signed URLs:</strong> Cloud media files utilize short-lived cryptographically signed presigned URLs accessible only to verified room members.</li>
              <li><strong>Zero AV Storage:</strong> Audio and video streams are processed in transient memory by media relays with zero recording to persistent disks.</li>
            </ul>
          </div>
        </section>

        {/* 13. Policy Updates */}
        <section id="s-13" className="space-y-4">
          <h2>
            <LegalNum n="13" />
            Changes to This Privacy Policy
          </h2>
          <p className="text-gray-300">
            We may update this Privacy Policy from time to time to reflect improvements to our app, changes in technology, or legal requirements. When updates occur, we will revise the &ldquo;Last Updated&rdquo; date at the top of this page. For significant material changes, we will provide additional notice through the application or website.
          </p>
        </section>

        {/* 14. Contact Us */}
        <section id="s-14" className="space-y-4">
          <h2>
            <LegalNum n="14" />
            Contact Us &amp; Grievance Redressal
          </h2>
          <div className="p-5 sm:p-6 rounded-xl bg-purple-500/10 border border-purple-400/20 text-gray-300 space-y-3">
            <p>
              If you have any questions, concerns, or requests regarding this Privacy Policy, your personal data, or data deletion, please reach out to our Data Protection &amp; Support Team:
            </p>
            <div className="space-y-1.5 text-gray-200">
              <div>
                <strong>Support &amp; Privacy Contact:</strong>{" "}
                <a
                  href={`mailto:${SITE_CONFIG.supportEmail}`}
                  className="text-purple-300 hover:text-white underline"
                >
                  {SITE_CONFIG.supportEmail}
                </a>
              </div>
              <div>
                <strong>Platform Operator:</strong> {SITE_CONFIG.creatorName}
              </div>
              <div>
                <strong>Project Repository:</strong>{" "}
                <a
                  href={SITE_CONFIG.githubRepo}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-purple-300 hover:text-white underline"
                >
                  {SITE_CONFIG.githubRepo}
                </a>
              </div>
            </div>
          </div>
        </section>
    </LegalShell>
  );
}
