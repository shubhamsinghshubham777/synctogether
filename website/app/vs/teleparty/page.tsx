import type { Metadata } from "next";
import { ComparisonPage } from "@/components/ComparisonPage";

export const metadata: Metadata = {
  title: "Teleparty Alternative for Downloaded Movies and Local Files",
  description:
    "Teleparty syncs Netflix, Disney+ and Prime Video in Chrome. SyncTogether syncs the video files already on your computer, plus YouTube, with voice and facecams. An honest comparison.",
  alternates: { canonical: "/vs/teleparty" },
};

export default function VsTelepartyPage() {
  return (
    <ComparisonPage
      competitor="Teleparty"
      eyebrow="Comparison"
      headline={
        <>
          Teleparty alternative for{" "}
          <span className="text-gradient-brand">your own video files</span>
        </>
      }
      intro="Teleparty (formerly Netflix Party) is a Chrome extension that keeps a streaming service in sync across browsers. It is free, it is good at that, and if everything you watch together lives on Netflix you probably do not need anything else. The gap opens the moment the thing you want to watch is a file on your computer."
      lastChecked="2026-09-24"
      rows={[
        { feature: "Netflix, Disney+, Prime Video, HBO", ours: "no", theirs: "yes" },
        { feature: "Local video files (MKV, MP4, 4K HDR)", ours: "yes", theirs: "no" },
        { feature: "YouTube", ours: "yes", theirs: "partial" },
        { feature: "Works without a browser extension", ours: "yes", theirs: "partial" },
        { feature: "Everyone needs their own subscription", ours: "no", theirs: "yes" },
        { feature: "Voice chat", ours: "yes", theirs: "Premium only" },
        { feature: "Video facecams beside the film", ours: "yes", theirs: "Premium only" },
        { feature: "Text chat", ours: "yes", theirs: "yes" },
        { feature: "Host can share the file with the room", ours: "yes", theirs: "no" },
        { feature: "Platforms", ours: "Mac, Windows", theirs: "Chrome, Edge, Opera, Mac, Android" },
        { feature: "Price", ours: "Free, Premium $3.99/mo", theirs: "Free, Premium $3.99/mo" },
      ]}
      sections={[
        {
          heading: "They solve different halves of the problem",
          body: [
            "Teleparty is a browser extension, so it can only sync what a browser is already playing. That makes it excellent for the big streaming catalogues and structurally incapable of touching a file sitting in your downloads folder. There is no version of Teleparty that plays your own MKV.",
            "SyncTogether is a native desktop app built around the opposite case. It opens the file locally on each machine with hardware-accelerated playback, and keeps play, pause and seek aligned across everyone in the room. For a 4K HDR file with multiple audio tracks and subtitles, this is the difference between watching it properly and not watching it at all.",
          ],
        },
        {
          heading: "Nobody needs a second subscription",
          body: [
            "Teleparty requires every person in the room to hold their own active subscription to whatever you are watching. For two people that is often fine. For a film club of eight, or for a couple where one person pays for a service the other does not, it quietly becomes the blocker.",
            "SyncTogether has no such requirement, because the room is pointed at a file or a YouTube link rather than at an account. Joining a room does not even require creating an account.",
          ],
        },
        {
          heading: "What happens when only one of you has the file",
          body: [
            "The usual failure of local-file sync is that one person has the video and the other does not, and the evening turns into a file transfer. SyncTogether lets the host upload the file to the room so everyone else streams it directly, without hunting down their own copy first. Nobody counts down from three.",
            "Signed-in free accounts can share files up to 2 GB within a weekly allowance; Premium raises the limit to 10 GB per file with no weekly cap. Guests can join a shared room but cannot upload.",
          ],
        },
        {
          heading: "Talking during the film",
          body: [
            "Teleparty's free tier gives you a text sidebar. Voice and video chat exist, but only Premium members can turn on a camera or microphone, so most groups on the free tier end up running a Discord call alongside the extension - two apps, two sets of settings.",
            "SyncTogether puts low-latency voice and optional video facecams in the same window as the film, so reacting to a scene does not cost you the scene.",
          ],
        },
      ]}
      verdictFor={[
        "You watch downloaded files, rips, or anything not on a streaming service",
        "You want to see and hear each other while the film runs",
        "Not everyone in the room has the same subscriptions",
        "Only one of you has the file, and you would rather not send a 6 GB transfer",
        "You care about proper playback of high-bitrate files, subtitles and audio tracks",
      ]}
      verdictAgainst={[
        "Everything you watch together is on Netflix, Disney+, Prime Video or HBO",
        "You genuinely prefer working inside a browser tab",
        "You are on Linux or ChromeOS, which SyncTogether does not support",
        "Text chat beside the film is all the conversation you want",
        "Your group already pays for Teleparty Premium and its voice chat is enough",
      ]}
    />
  );
}
