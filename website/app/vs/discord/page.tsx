import type { Metadata } from "next";
import { ComparisonPage } from "@/components/ComparisonPage";

export const metadata: Metadata = {
  title: "Better Than Discord Screen Share for Watching Movies Together",
  description:
    "Discord screen share compresses your film to a blurry, stuttering stream and drifts out of sync with the audio. SyncTogether plays the file natively on both machines instead. An honest comparison.",
  alternates: { canonical: "/vs/discord" },
};

export default function VsDiscordPage() {
  return (
    <ComparisonPage
      competitor="Discord"
      eyebrow="Comparison"
      headline={
        <>
          Watching a film over Discord{" "}
          <span className="text-gradient-brand">looks like a potato</span>
        </>
      }
      intro="Discord screen share is where almost everyone starts, because the call is already running. It is also the wrong tool for a two-hour film, and everybody who has tried it knows exactly why: the picture is soft, the motion stutters, the audio slides out of sync, and one of you is burning a CPU core to make that happen. The problem is not your internet. It is what screen sharing fundamentally is."
      rows={[
        { feature: "Full source quality (1080p, 4K, HDR)", ours: "yes", theirs: "no" },
        { feature: "Needs Nitro for higher resolution", ours: "no", theirs: "yes" },
        { feature: "Host's CPU encodes the whole film", ours: "no", theirs: "yes" },
        { feature: "Audio and video stay in sync", ours: "yes", theirs: "partial" },
        { feature: "Everyone can pause and seek", ours: "yes", theirs: "no" },
        { feature: "Subtitles and audio track selection", ours: "yes", theirs: "no" },
        { feature: "Voice chat", ours: "yes", theirs: "yes" },
        { feature: "Video facecams", ours: "yes", theirs: "yes" },
        { feature: "Works if the host's connection dips", ours: "yes", theirs: "no" },
        { feature: "Host can share the file with the room", ours: "yes", theirs: "no" },
        { feature: "YouTube together", ours: "yes", theirs: "partial" },
        { feature: "Price", ours: "Free, Premium $3.99/mo", theirs: "Free, Nitro $9.99/mo" },
      ]}
      sections={[
        {
          heading: "Screen sharing re-encodes your film in real time",
          body: [
            "When you share your screen, Discord captures the pixels your player is drawing, compresses them live at a low bitrate, and sends that stream to everyone. Your carefully encoded 15 Mbps file becomes a few megabits of real-time video conferencing codec. Dark scenes band, fast motion smears, and film grain is destroyed because compression treats it as noise to discard.",
            "SyncTogether never streams the picture. Each machine opens the video file itself and plays it natively with hardware acceleration, and only tiny control messages - play, pause, seek - travel over the network. What you see is the file, at full quality, on both ends.",
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
            "In a screen share, the host's upload speed is the ceiling for the entire room, and the host's CPU is doing real-time video encoding on top of decoding and playing the film. A dropped frame or a brief network dip hits everyone at once.",
            "With local playback there is nothing to drop. A momentary network problem delays a pause message by a fraction of a second; it does not degrade the picture. SyncTogether also resynchronises automatically if anyone drifts more than about a second and a half.",
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
        "You are on Linux or mobile, which SyncTogether does not support",
      ]}
    />
  );
}
