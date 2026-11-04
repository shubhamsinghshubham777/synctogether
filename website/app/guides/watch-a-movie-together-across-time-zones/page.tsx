import type { Metadata } from "next";
import { GuidePage } from "@/components/GuidePage";

export const metadata: Metadata = {
  title: "How to Watch a Movie Together Across Time Zones",
  description:
    "How to watch a movie with your partner when you are in different cities or time zones: pick a time, match the file, keep playback in sync and talk during the film.",
  alternates: { canonical: "/guides/watch-a-movie-together-across-time-zones" },
};

export default function WatchAMovieAcrossTimeZonesPage() {
  return (
    <GuidePage
      eyebrow="Guide"
      path="/guides/watch-a-movie-together-across-time-zones"
      updated="November 2026"
      title={
        <>
          How to watch a movie together{" "}
          <span className="text-beam-500">across time zones.</span>
        </>
      }
      answer="Pick a start time you both see on your own clock, make sure you have the same version of the film, and use a tool that keeps play, pause and seek aligned for both of you. Then add a voice or video call so you can react together. Streaming-service extensions, Syncplay and SyncTogether each cover different cases."
      sections={[
        {
          heading: "1. Agree a time that works on both clocks",
          body: [
            "Time zones are the part that quietly ruins a date. Write the start time down for both cities, for example 8:00 pm in one and 1:30 am in the other, so nobody does the sum in their head on the night.",
            "A world-clock or meeting-planner site shows overlapping evening hours for two cities. Pick a recurring slot, such as every second Friday, rather than negotiating each time. A fixed slot is what turns a one-off into a ritual.",
          ],
        },
        {
          heading: "2. Make sure you are watching the same thing",
          body: [
            "On a streaming service, you are both watching the same catalogue title, but only if it is available in both countries. Catalogues differ by region, so check before you plan the evening.",
            "With a video file, the version matters: a different release can have a different intro, a different cut or a slightly different length, and then the two of you drift apart from the first scene. Agree on one file and, if you can, compare the length shown in each player before you start.",
          ],
        },
        {
          heading: "3. Choose how you will stay in sync",
          items: [
            {
              title: "Count down and press play together",
              text: "Free and needs nothing installed. The catch is that it drifts: a pause by one person means the other has to match it by hand, and neither of you can rewind a line of dialogue without asking.",
            },
            {
              title: "A browser extension for streaming services",
              text: "Teleparty keeps Netflix, Disney+, Prime Video and similar services in sync inside Chrome-based browsers. It only works with those services, and each person needs their own subscription.",
            },
            {
              title: "Syncplay for local files",
              text: "Free, open source and long established. It syncs a video file between players such as mpv or VLC, on Windows, Mac and Linux. You install and configure a player, and everyone needs a copy of the file.",
            },
            {
              title: "SyncTogether for local files and YouTube",
              text: "A desktop app for Mac and Windows with its own player. Anyone in the room can pause or seek and everyone follows, and voice and facecams are in the same window. A signed-in host can upload the file so the other person streams it instead of finding their own copy.",
            },
            {
              title: "Screen sharing on a video call",
              text: "Already on every device, and good for a short clip. For a full film, only the person sharing has the remote, and what the other person sees is a live copy of the sharer's screen.",
            },
          ],
        },
        {
          heading: "4. Do a two-minute check before the night",
          body: [
            "Test sound, subtitles and the call a day earlier. Most failed movie nights are a muted microphone or a missing subtitle track, not the film.",
            "Decide in advance who handles the controls. In some tools only one person can pause; in others anyone can. Agreeing the rule, such as \"either of us can pause whenever we like\", saves the first argument.",
          ],
        },
        {
          heading: "5. Talk during the film, on purpose",
          body: [
            "The reason to watch together instead of separately is the reaction beside you. Keep a voice or video call open, and agree what is allowed: talking over the film, pausing for a bathroom break, rewinding to catch a line.",
            "If you want to see each other's faces without covering the screen, use a tool that puts the video tiles beside the film rather than a second window on top of it.",
          ],
        },
        {
          heading: "A simple routine that keeps it going",
          items: [
            {
              title: "Same slot, every time",
              text: "A recurring night beats a good plan you keep rescheduling.",
            },
            {
              title: "Take turns choosing",
              text: "Alternate who picks the film, and never veto the other person's choice twice in a row.",
            },
            {
              title: "Start with a five-minute catch-up",
              text: "Talk before you press play, so the film is not the only thing you say to each other.",
            },
            {
              title: "Keep a list of what you have watched",
              text: "A shared note with titles and one-line ratings becomes a record of your relationship.",
            },
          ],
        },
      ]}
      cta={{
        heading: "Try it for your next movie night.",
        text: "SyncTogether is free on Mac and Windows. Create a room, send your partner the invite link, and press play together. Joining needs no account.",
      }}
    />
  );
}
