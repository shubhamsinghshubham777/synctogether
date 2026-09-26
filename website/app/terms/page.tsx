import type { Metadata } from "next";
import { LegalShell, LegalNum } from "@/components/LegalShell";
import { SITE_CONFIG } from "@/lib/constants";

const TOC = [
  { id: "s-1", n: "01", label: "Nature of the Service" },
  { id: "s-2", n: "02", label: "User Accounts & Identities" },
  { id: "s-3", n: "03", label: "Acceptable Use" },
  { id: "s-4", n: "04", label: "Premium Subscriptions & Billing" },
  { id: "s-5", n: "05", label: "User Content & Privacy" },
  { id: "s-6", n: "06", label: "Copyright, Moderation & Termination" },
  { id: "s-7", n: "07", label: "Service Availability & Disclaimer" },
  { id: "s-8", n: "08", label: "Governing Law" },
  { id: "s-9", n: "09", label: "Contact Us" },
];

export const metadata: Metadata = {
  title: "Terms of Service",
  description: "Terms of Service and conditions for using the SyncTogether application and services.",
};

export default function TermsPage() {
  const lastUpdated = "September 20, 2026";

  return (
    <LegalShell
      current="/terms"
      kicker="Agreement"
      title="Terms of Service"
      dek="The short version: be decent to the people in your room, only share what you have the right to share, and we keep the projector running."
      toc={TOC}
      dates={[{ label: "Updated", value: lastUpdated }]}
    >
        <section id="s-1" className="space-y-3">
          <h2>
            <LegalNum n="1" />
            Nature of the Service
          </h2>
          <p>
            SyncTogether is a media synchronization software platform that enables participants to synchronize playback state (play, pause, seek, audio track) for locally stored media files, cloud-shared videos, and public YouTube videos across connected devices.
          </p>
          <div className="p-4 rounded-xl bg-purple-500/10 border border-purple-400/20 text-purple-200 text-sm">
            <strong>Important:</strong> In Local Sync mode, SyncTogether does not host or distribute media files. All participants possess their own local copy. In Cloud Media Sharing mode, room hosts may upload videos for temporary streaming to room guests, subject to automated session expiration.
          </div>
        </section>

        <section id="s-2" className="space-y-3">
          <h2>
            <LegalNum n="2" />
            User Accounts &amp; Identities
          </h2>
          <p>
            You may use SyncTogether as a Guest without registration, or authenticate using Google OAuth, Sign in with Apple, or Email sign-in. You agree to maintain the security of your account and take full responsibility for all activities occurring under your identity.
          </p>
        </section>

        <section id="s-3" className="space-y-3">
          <h2>
            <LegalNum n="3" />
            Acceptable Use
          </h2>
          <p>You agree not to:</p>
          <ul className="list-disc list-inside space-y-2 text-gray-300 text-sm sm:text-base">
            <li>Use the service to broadcast abusive, harmful, or illegal communications.</li>
            <li>Interfere with, overburden, or compromise the integrity of our real-time relay infrastructure.</li>
            <li>Attempt to reverse-engineer server APIs or bypass room limits.</li>
            <li>
              Upload, stream, or share any material you do not own or have permission to share.
              Cloud Media Sharing is for content you have the right to distribute to the people
              in your room.
            </li>
            <li>Harass, threaten, impersonate, or bully other participants.</li>
          </ul>
        </section>

        <section id="s-4" className="space-y-3">
          <h2>
            <LegalNum n="4" />
            Premium Subscriptions &amp; Billing
          </h2>
          <p>
            Paid subscriptions provide enhanced features including persistent rooms, 16-member limits, and video facecams. All subscriptions are processed securely through our authorized Merchant of Record.
          </p>
          <p>
            Subscriptions are billed on a recurring monthly or annual basis. We reserve the right to modify subscription pricing with at least 30 days prior notice.
          </p>
        </section>

        <section id="s-5" className="space-y-3">
          <h2>
            <LegalNum n="5" />
            User Content &amp; Privacy
          </h2>
          <p>
            In Local Sync mode, we do not upload or store your media files or full directory file paths. In Cloud Media Sharing mode, host-uploaded video files are temporarily hosted in encrypted storage and permanently deleted upon room closure or expiry. Room chat messages and quick reactions are session-scoped and purged automatically upon room expiration or closure. For complete details, see our <a href="/privacy" className="text-purple-300 hover:text-white underline">Privacy Policy</a>.
          </p>
        </section>

        <section id="s-6" className="space-y-3">
          <h2>
            <LegalNum n="6" />
            Copyright, Moderation &amp; Termination
          </h2>
          <p>
            You are responsible for the content you upload or share. If you believe material
            shared through SyncTogether infringes your copyright, our{" "}
            <a href="/dmca" className="text-purple-300 hover:text-white underline">Copyright &amp; DMCA Policy</a>{" "}
            explains how to send a notice to our registered designated agent, and how to file a
            counter-notification.
          </p>
          <p>
            You can report abusive behaviour or infringing material from inside the app, from a
            chat message or the member list, and you can block anyone you do not wish to hear
            from. A block hides their messages and camera everywhere, in every room.
          </p>
          <p>
            We remove content that violates these Terms, and we terminate, in appropriate
            circumstances, the accounts of repeat copyright infringers and of anyone who harasses
            or abuses other participants.
          </p>
        </section>

        <section id="s-7" className="space-y-3">
          <h2>
            <LegalNum n="7" />
            Service Availability &amp; Disclaimer
          </h2>
          <p>
            SyncTogether is provided on an &ldquo;as is&rdquo; and &ldquo;as available&rdquo; basis without warranties of any kind. We do not guarantee uninterrupted or error-free operation.
          </p>
        </section>

        <section id="s-8" className="space-y-3">
          <h2>
            <LegalNum n="8" />
            Governing Law
          </h2>
          <p>
            These Terms shall be governed by and construed in accordance with the laws of India, without regard to its conflict of law provisions.
          </p>
        </section>

        <section id="s-9" className="space-y-3">
          <h2>
            <LegalNum n="9" />
            Contact Us
          </h2>
          <p>
            If you have questions regarding these Terms, please contact us at:{" "}
            <a
              href={`mailto:${SITE_CONFIG.supportEmail}`}
              className="text-purple-300 hover:text-white underline"
            >
              {SITE_CONFIG.supportEmail}
            </a>.
          </p>
        </section>
    </LegalShell>
  );
}
