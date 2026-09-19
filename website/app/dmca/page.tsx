import type { Metadata } from "next";
import { GlassPanel } from "@/components/GlassPanel";
import { DMCA_AGENT, SITE_CONFIG } from "@/lib/constants";

export const metadata: Metadata = {
  title: "Copyright & DMCA Policy",
  description:
    "How to report copyright infringement on SyncTogether, our designated agent for copyright notices, and our counter-notification and repeat infringer policies.",
};

export default function DmcaPage() {
  const lastUpdated = "September 20, 2026";

  return (
    <div className="relative py-12 md:py-20 px-4 sm:px-6 lg:px-8 max-w-4xl mx-auto space-y-12">
      <div className="space-y-3 text-center sm:text-left">
        <span className="text-xs font-mono text-purple-400 font-bold uppercase tracking-wider">
          Legal
        </span>
        <h1 className="text-4xl sm:text-5xl font-extrabold text-white tracking-tight font-[family-name:var(--font-space-grotesk)]">
          Copyright &amp; DMCA Policy
        </h1>
        <p className="text-xs text-gray-400 font-mono">
          Last Updated: {lastUpdated}
        </p>
      </div>

      <GlassPanel className="p-8 sm:p-10 space-y-8 text-sm sm:text-base text-gray-300 leading-relaxed border-purple-500/20">
        <section className="space-y-3">
          <h2 className="text-xl sm:text-2xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
            1. Our Position
          </h2>
          <p>
            SyncTogether respects the intellectual property rights of others and expects the
            people who use it to do the same. We respond to clear notices of alleged copyright
            infringement that comply with the Digital Millennium Copyright Act (DMCA).
          </p>
          <div className="p-4 rounded-xl bg-purple-500/10 border border-purple-400/20 text-purple-200 text-sm">
            <strong>Where content actually lives:</strong> in Local Sync mode SyncTogether hosts
            nothing at all &ndash; each participant plays their own copy of a file from their own
            device, and only playback position is exchanged. In Cloud Media Sharing mode a room
            host may upload a video so that guests without a copy can stream it; those files are
            stored temporarily and deleted when the room closes or expires. Notices under this
            policy concern content uploaded through Cloud Media Sharing.
          </div>
        </section>

        <section className="space-y-3">
          <h2 className="text-xl sm:text-2xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
            2. Designated Agent for Copyright Notices
          </h2>
          <p>
            We have registered a designated agent with the United States Copyright Office
            (registration number{" "}
            <span className="font-mono text-purple-300">{DMCA_AGENT.registrationNumber}</span>).
            Send copyright notices to:
          </p>
          <div className="p-4 rounded-xl bg-white/5 border border-white/10 font-mono text-sm text-gray-200 space-y-1">
            <div>{DMCA_AGENT.agentName}</div>
            <div>{DMCA_AGENT.serviceProvider}</div>
            {DMCA_AGENT.address.map((line) => (
              <div key={line}>{line}</div>
            ))}
            <div className="pt-2">
              <a
                href={`mailto:${DMCA_AGENT.email}`}
                className="text-purple-300 hover:text-white underline"
              >
                {DMCA_AGENT.email}
              </a>
            </div>
          </div>
          <p className="text-sm text-gray-400">
            Email reaches us fastest. Please use this address only for copyright matters &ndash;
            for anything else, write to{" "}
            <a
              href={`mailto:${SITE_CONFIG.supportEmail}`}
              className="text-purple-300 hover:text-white underline"
            >
              {SITE_CONFIG.supportEmail}
            </a>
            .
          </p>
        </section>

        <section className="space-y-3">
          <h2 className="text-xl sm:text-2xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
            3. Sending a Takedown Notice
          </h2>
          <p>
            To be effective under 17 U.S.C. &sect; 512(c)(3), your notice must be a written
            communication that includes substantially all of the following:
          </p>
          <ul className="list-decimal list-inside space-y-2 text-gray-300 text-sm sm:text-base">
            <li>
              A physical or electronic signature of the copyright owner, or a person authorised to
              act on their behalf.
            </li>
            <li>
              Identification of the copyrighted work claimed to have been infringed, or a
              representative list if the notice covers multiple works.
            </li>
            <li>
              Identification of the material claimed to be infringing, with enough detail for us
              to locate it &ndash; for SyncTogether this means the <strong>room code</strong> and,
              where you have it, the approximate date and time it was shared.
            </li>
            <li>Your name, postal address, telephone number and email address.</li>
            <li>
              A statement that you have a good faith belief that the use is not authorised by the
              copyright owner, its agent, or the law.
            </li>
            <li>
              A statement that the information in the notice is accurate and, under penalty of
              perjury, that you are authorised to act on behalf of the owner.
            </li>
          </ul>
          <p className="text-sm text-gray-400">
            Rooms are short-lived by design and uploaded files are deleted automatically when a
            room closes, so please send notices promptly &ndash; material may already be gone by
            the time a notice arrives.
          </p>
        </section>

        <section className="space-y-3">
          <h2 className="text-xl sm:text-2xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
            4. What We Do
          </h2>
          <p>
            On receiving a valid notice we remove or disable access to the material, delete the
            stored file, and make a reasonable attempt to notify the person who uploaded it,
            including a copy of the notice.
          </p>
        </section>

        <section className="space-y-3">
          <h2 className="text-xl sm:text-2xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
            5. Counter-Notification
          </h2>
          <p>
            If you believe your material was removed by mistake or misidentification, you may send
            a counter-notification under 17 U.S.C. &sect; 512(g)(3) to the agent above, including:
            your signature; identification of the removed material and where it appeared; a
            statement under penalty of perjury that you have a good faith belief it was removed as
            a result of mistake or misidentification; and your name, address and telephone number,
            together with a statement that you consent to the jurisdiction of the federal court
            for the district in which you live (or, if outside the United States, any district in
            which we may be found) and that you will accept service of process from the party who
            filed the notice.
          </p>
          <p>
            If we receive a valid counter-notification we may restore the material in 10 to 14
            business days, unless the original complainant notifies us that they have filed an
            action seeking a court order.
          </p>
        </section>

        <section className="space-y-3">
          <h2 className="text-xl sm:text-2xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
            6. Repeat Infringers
          </h2>
          <p>
            We terminate, in appropriate circumstances, the accounts of people who are repeat
            infringers. Termination removes access to hosting and sharing features and to any
            rooms held under that account.
          </p>
        </section>

        <section className="space-y-3">
          <h2 className="text-xl sm:text-2xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
            7. Misrepresentations
          </h2>
          <p>
            Under 17 U.S.C. &sect; 512(f), anyone who knowingly materially misrepresents that
            material is infringing &ndash; or that it was removed by mistake &ndash; may be liable
            for damages, including costs and legal fees. Please be sure before you send a notice.
          </p>
        </section>

        <section className="space-y-3">
          <h2 className="text-xl sm:text-2xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
            8. Reporting From Inside the App
          </h2>
          <p>
            You can also report content without writing an email. In any room, open the chat or
            the member list, choose the flag icon beside a person or a message, and pick{" "}
            <strong>Copyright infringement</strong>. Reports reach our moderation queue with the
            room and the material attached. For a formal DMCA notice with legal effect, use the
            designated agent above.
          </p>
        </section>
      </GlassPanel>
    </div>
  );
}
