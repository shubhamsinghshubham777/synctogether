import type { Metadata } from "next";
import { ComparisonPage } from "@/components/ComparisonPage";
import { PRICING_TIERS } from "@/lib/constants";

export const metadata: Metadata = {
  title: "Better Than Discord Screen Share for Watching Movies Together",
  description:
    "Discord screen share streams one person's screen to everyone, so only they hold the remote. SyncTogether plays the file on every machine, so anyone can pause, rewind and choose subtitles. An honest comparison.",
  alternates: { canonical: "/vs/discord" },
};

export default function VsDiscordPage() {
  return (
    <ComparisonPage
      competitor="Discord"
      eyebrow="Comparison"
      headline={
        <>
          Watching a film over Discord:{" "}
          <span className="text-beam-500">everyone gets a remote.</span>
        </>
      }
      answer="Discord screen share works well for sharing a screen. SyncTogether is built for watching a film together: every machine plays the file itself, so anyone can pause, rewind or pick their own subtitles and audio track, and nobody's computer has to stream the film to everyone else. Voice and facecams sit in the same window, on Mac and Windows."
      intro="Discord screen share is where almost everyone starts, because the call is already running. It is built for showing a screen, though, not for a two-hour film that two people want to pause, rewind and talk over. The difference is not your internet. It is what screen sharing is."
      lastChecked="2026-11-04"
      rows={[
        { feature: "Everyone plays the original file", ours: "yes", theirs: "no" },
        { feature: "Needs Nitro for higher resolution", ours: "no", theirs: "yes" },
        { feature: "Host's CPU encodes the whole film", ours: "no", theirs: "yes" },
        { feature: "Everyone can pause and seek", ours: "yes", theirs: "no" },
        { feature: "Per-viewer subtitles and audio tracks", ours: "yes", theirs: "no" },
        { feature: "Voice chat", ours: "yes", theirs: "yes" },
        { feature: "Video facecams", ours: "Patron (Free gets a short trial)", theirs: "yes" },
        { feature: "Host's upload speed limits what everyone sees", ours: "no", theirs: "yes" },
        { feature: "Host can share the file with the room", ours: "yes", theirs: "no" },
        { feature: "YouTube together", ours: "yes", theirs: "yes" },
        { feature: "Price", ours: `Free, Patron ${PRICING_TIERS.premium.price.usdMonthly}/mo`, theirs: "Free, Nitro $9.99/mo" },
      ]}
      sections={[
        {
          heading: "Screen sharing streams a copy; SyncTogether plays the file",
          body: [
            "When you share your screen, Discord captures what your player is drawing, encodes it live and sends that stream to everyone. It does that job well, and for a clip or a quick look at something it is the right tool. But what everyone else sees is a live copy of the host's screen, shaped by the host's settings, machine and upload.",
            "SyncTogether never streams the picture. Each machine opens the video file itself and plays it natively with hardware acceleration, and only tiny control messages (play, pause, seek) travel over the network. What each person watches is the file itself, on their own machine.",
          ],
        },
        {
          heading: "Only the host has a remote",
          body: [
            "On a Discord share, the film is playing on the host's machine and nowhere else. If the other person needs to pause for two minutes, they have to ask, and the host has to be at their keyboard. Rewinding to catch a line of dialogue is a negotiation.",
            "Because SyncTogether is playing the file on every machine, anyone can pause, skip back ten seconds or scrub, and everyone else follows instantly. If the host wants sole control, there is a transport lock for that, but it is a choice rather than a limitation.",
          ],
        },
        {
          heading: "Your connection stops being everyone's problem",
          body: [
            "In a screen share, the host's upload speed is the ceiling for the entire room, and the host's CPU is doing real-time video encoding on top of decoding and playing the film. Whatever happens on the host's machine or connection happens to everyone watching.",
            "With local playback there is nothing to drop. A momentary network problem delays a pause message by a fraction of a second; the picture is not travelling over the network at all. SyncTogether also resynchronises automatically if anyone drifts more than about a second and a half.",
          ],
        },
        {
          heading: "Subtitles, audio tracks and everything else a real player does",
          body: [
            "A shared screen is a flat image, so there are no subtitle options, no switching to the original language audio, no per-viewer settings at all. Whatever the host picked is what everyone gets, burned into the stream.",
            "Each person in a SyncTogether room is running an actual media player, so subtitles and audio tracks are per-person choices. One of you can watch with subtitles on and the other without.",
          ],
        },
        {
          heading: "You can keep the Discord call if you want",
          body: [
            "Nothing here requires leaving Discord. Plenty of people run the voice call in Discord out of habit and use SyncTogether purely for the video, and that works fine.",
            "But SyncTogether has voice and facecams built in, so the simpler setup is one window with the film, the faces and the conversation all in it.",
          ],
        },
      ]}
      verdictFor={[
        "You are watching a full-length film rather than glancing at something for two minutes",
        "Picture quality, subtitles or audio tracks matter to you",
        "You want both people to be able to pause and rewind",
        "The host's upload speed or laptop fan is currently the limiting factor",
        "Only one of you has the file",
      ]}
      verdictAgainst={[
        "You are showing someone something short, or a window that is not a video at all",
        "You need to share an app, a game or a whole desktop rather than a film",
        "Your group will not install anything new, ever",
        "You need a Linux client",
      ]}
    />
  );
}
