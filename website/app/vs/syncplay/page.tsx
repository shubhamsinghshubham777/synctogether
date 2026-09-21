import type { Metadata } from "next";
import { ComparisonPage } from "@/components/ComparisonPage";

export const metadata: Metadata = {
  title: "Syncplay Alternative with Voice, Video and File Sharing",
  description:
    "Syncplay is free, open source and excellent at syncing local files. SyncTogether adds voice, facecams, and host file sharing so the other person does not need their own copy. An honest comparison.",
  alternates: { canonical: "/vs/syncplay" },
};

export default function VsSyncplayPage() {
  return (
    <ComparisonPage
      competitor="Syncplay"
      eyebrow="Comparison"
      headline={
        <>
          Syncplay alternative with{" "}
          <span className="text-gradient-brand">voice and facecams built in</span>
        </>
      }
      intro="Syncplay is free, open source, cross-platform and genuinely good at the hard part: keeping local video files in lockstep across machines. It has been doing this for over a decade. If it already works for you, there is a reasonable argument that you should keep using it, and this page will not pretend otherwise. What follows is what SyncTogether does that Syncplay does not."
      rows={[
        { feature: "Local file sync", ours: "yes", theirs: "yes" },
        { feature: "Free and open source", ours: "partial", theirs: "yes" },
        { feature: "Linux support", ours: "no", theirs: "yes" },
        { feature: "Self-hostable server", ours: "yes", theirs: "yes" },
        { feature: "Requires installing and configuring a player", ours: "no", theirs: "yes" },
        { feature: "Built-in voice chat", ours: "yes", theirs: "no" },
        { feature: "Video facecams beside the film", ours: "yes", theirs: "no" },
        { feature: "Host can share the file with the room", ours: "yes", theirs: "no" },
        { feature: "YouTube", ours: "yes", theirs: "no" },
        { feature: "Everyone must already have the file", ours: "no", theirs: "yes" },
        { feature: "Animated reactions and chat", ours: "yes", theirs: "partial" },
        { feature: "Platforms", ours: "Mac, Windows", theirs: "Mac, Windows, Linux" },
      ]}
      sections={[
        {
          heading: "Everyone having the same file is the real friction",
          body: [
            "Syncplay's model assumes every person in the room already has the video, and ideally the same cut of it. In practice that assumption is where most watch parties die: someone has a different release, someone's copy is 90 seconds shorter because of an intro, someone does not have it at all, and the plan becomes a file transfer over a messaging app that caps out at 2 GB.",
            "SyncTogether lets the host upload the file to the room, and everyone else streams it directly. The room also checks that everyone has the canonical media open before anything can play, and tells you by name who is still loading or holding a different file, rather than letting the group drift apart silently.",
          ],
        },
        {
          heading: "Talking to each other is not a separate app",
          body: [
            "Syncplay has a text chat box. The standard setup therefore ends up being Syncplay plus a Discord call in another window, which works, but means two apps to configure and no relationship between the call and the film.",
            "SyncTogether has low-latency voice and optional video facecams in the same window as the video. Seeing someone's face during a scene is most of the reason to watch together rather than separately, and it is the one thing a sync tool without AV can never give you.",
          ],
        },
        {
          heading: "Setup cost",
          body: [
            "Syncplay is a front-end for a media player you supply. You install Syncplay, install mpv or VLC, point one at the other, and either pick a public server or run your own. None of that is hard for the kind of person who reads release notes, and all of it is a wall for the person you are trying to watch a film with.",
            "SyncTogether ships its own player. Install it, create a room, send the link. The person receiving the link does not need an account.",
          ],
        },
        {
          heading: "Where Syncplay is straightforwardly better",
          body: [
            "It runs on Linux and SyncTogether does not. It is fully open source under a free licence, where SyncTogether is source-available under PolyForm Noncommercial. It supports players and formats SyncTogether does not, and it has had a decade of edge cases beaten out of it.",
            "If you are a Linux user, or you want a tool with no commercial dimension at all, Syncplay is the right answer and you should use it.",
          ],
        },
      ]}
      verdictFor={[
        "You want to see and hear each other while the film runs",
        "Only one of you has the file, or the copies do not match",
        "The person you are watching with will not install and configure two apps",
        "You want YouTube in the same tool",
        "You are on Mac or Windows",
      ]}
      verdictAgainst={[
        "You are on Linux",
        "Fully open source under a free licence matters to you",
        "Your group already has Syncplay working and everyone has matching files",
        "You want a specific media player that SyncTogether does not use",
        "You already run a voice call separately and are happy with it",
      ]}
    />
  );
}
