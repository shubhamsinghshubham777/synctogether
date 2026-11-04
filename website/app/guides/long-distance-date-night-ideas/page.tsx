import type { Metadata } from "next";
import { GuidePage } from "@/components/GuidePage";

export const metadata: Metadata = {
  title: "24 Long-Distance Date Night Ideas That Actually Work Over Video",
  description:
    "24 long-distance date night ideas for couples in different cities or time zones: cooking, games, movies, walks and more, with what you need for each.",
  alternates: { canonical: "/guides/long-distance-date-night-ideas" },
};

export default function LongDistanceDateNightIdeasPage() {
  return (
    <GuidePage
      eyebrow="Guide"
      path="/guides/long-distance-date-night-ideas"
      updated="November 2026"
      title={
        <>
          24 long-distance date night ideas{" "}
          <span className="text-beam-500">that work over video.</span>
        </>
      }
      answer="The long-distance date nights that last are the ones with a shared task and a ritual: cook the same recipe, play the same game, watch the same film at the same moment. Pick one that fits your time zones, do it on a fixed night, and keep the setup simple enough that you never skip it."
      sections={[
        {
          heading: "Cook and eat together",
          items: [
            {
              title: "Cook the same recipe at the same time",
              text: "Agree on a dish in advance so you both shop first. Prop a phone or laptop where you can see each other's counter. The mess and the substitutions are the fun part.",
            },
            {
              title: "Takeaway swap",
              text: "Order from a place in the other person's city and have it delivered to them while they do the same for you. Eat on the call and compare.",
            },
            {
              title: "Fancy dinner at home",
              text: "Dress up, set the table, light a candle and eat a proper three-course meal on video. Treating an ordinary Tuesday as an occasion is the whole point.",
            },
            {
              title: "Breakfast date across time zones",
              text: "If one of you is on an evening and the other on a morning, have breakfast for one and dinner for the other. It makes the time difference part of the date.",
            },
            {
              title: "Bake something and compare",
              text: "Same recipe, two ovens, two very different results. Judge each other's attempt honestly.",
            },
            {
              title: "Cocktail or mocktail night",
              text: "Pick a drink, send each other the ingredient list, and make it together. A tasting scorecard turns it into a game.",
            },
          ],
        },
        {
          heading: "Play together",
          items: [
            {
              title: "A two-player online game",
              text: "Pick one you can both run on your computers and stick with it for a few weeks so you improve together.",
            },
            {
              title: "Browser board games",
              text: "Chess, card games and trivia all work in a browser tab beside a video call. Keep score across the month.",
            },
            {
              title: "Virtual escape room",
              text: "Many escape rooms now run online for two players. Share a screen or use the room's own chat, and expect to be stuck on one puzzle for twenty minutes.",
            },
            {
              title: "Jigsaw puzzle on the same picture",
              text: "Buy the same physical puzzle, or use an online one, and race or collaborate while you talk.",
            },
            {
              title: "Draw and guess",
              text: "One of you draws a prompt, the other guesses. It is funnier the worse you both are at drawing.",
            },
            {
              title: "Question night",
              text: "Take turns asking questions from a list or a deck. It is the quietest idea on this list and often the one people remember.",
            },
          ],
        },
        {
          heading: "Watch together",
          items: [
            {
              title: "A film from your own collection",
              text: "Both of you open the same file and press play together. This is the classic movie night; the section below covers how to keep it in sync.",
            },
            {
              title: "A series, one episode per week",
              text: "A weekly episode gives you something to look forward to and talk about between dates.",
            },
            {
              title: "YouTube rabbit hole",
              text: "Pick a topic you are both curious about and follow the recommendations together, taking turns to choose the next video.",
            },
            {
              title: "Your favourite film from each other's childhood",
              text: "Each person picks one film that mattered to them growing up and explains why before it starts.",
            },
            {
              title: "A film festival at home",
              text: "Choose a theme, such as a director, a decade or a country, and watch one film a week. Rate each one at the end.",
            },
            {
              title: "Concert or live stream",
              text: "Many artists stream shows online. Watch one together, then compare setlists and favourites.",
            },
          ],
        },
        {
          heading: "Do something side by side",
          items: [
            {
              title: "Walk and talk",
              text: "Both of you go for a walk at the same time, with earbuds in, and describe what you can see.",
            },
            {
              title: "Learn something together",
              text: "A language, a short online course or a skill. Having a shared project keeps the conversation moving between dates.",
            },
            {
              title: "Plan the next visit",
              text: "Build the itinerary for your next trip together: places to eat, things to see, what to pack. The planning is a date in itself.",
            },
            {
              title: "Read the same book",
              text: "Agree on a chapter a week and talk about it on the call, or read aloud to each other.",
            },
            {
              title: "Stargazing night",
              text: "If your skies are clear at the same time, go outside and spot the same constellations, or use a sky map app.",
            },
            {
              title: "Write each other letters, then open them on the call",
              text: "Mail a handwritten letter and set a date to open it together on video.",
            },
          ],
        },
        {
          heading: "Making a movie night actually work",
          fullWidth: true,
          body: [
            "Of the ideas above, watching a film together is the one most couples try first and the one that most often goes wrong in the first five minutes: someone is a few seconds ahead, someone has a different cut of the film, and the evening starts with a countdown from three.",
            "Syncplay is a free, open-source way to keep a local video file in sync between two computers. Teleparty does the same for streaming services inside a browser. SyncTogether is a desktop app for Mac and Windows that keeps play, pause and seek aligned for a video file or YouTube link, with voice and facecams in the same window. Which one fits depends on what you watch and how much setup you want.",
          ],
        },
      ]}
      cta={{
        heading: "Movie night, even when you're apart.",
        text: "SyncTogether keeps a film on the same frame for both of you, with your faces beside it. Free on Mac and Windows; joining a room needs no account.",
      }}
    />
  );
}
