// Mirrors lib/rooms/reactions.dart (kReactions / kExtendedReactions) in the Flutter app.
// That file is the source of truth - keep this list and tool/fetch-web-emoji.mjs's
// manifest in sync with it, or the receive-side allow-list and what ships will drift.
export interface PTReaction {
  emoji: string;
  codepoint: string;
  label: string;
}

// No digest is pinned here on purpose. The Flutter app pins one because its CDN fetch
// feeds a receive-side allow-list - a trust boundary. On the web the static frame is
// already shipped and the animated fetch only ever upgrades a tile that is already
// rendering, so there is nothing to guard; the build-time pins that matter live in
// tool/fetch-web-emoji.mjs, which verifies every file before it writes one.

export const kReactions: PTReaction[] = [
  { emoji: "💖", codepoint: "1f496", label: "Love it" },
  { emoji: "👍", codepoint: "1f44d", label: "Nice" },
  { emoji: "🎉", codepoint: "1f389", label: "Party" },
  { emoji: "👏", codepoint: "1f44f", label: "Applause" },
  { emoji: "😂", codepoint: "1f602", label: "Hilarious" },
  { emoji: "😮", codepoint: "1f62e", label: "Whoa" },
  { emoji: "😢", codepoint: "1f622", label: "Sad" },
  { emoji: "🤔", codepoint: "1f914", label: "Hmm" },
];

export const kExtendedReactions: PTReaction[] = [
  { emoji: "🔥", codepoint: "1f525", label: "Fire" },
  { emoji: "🍿", codepoint: "1f37f", label: "Popcorn" },
  { emoji: "🤣", codepoint: "1f923", label: "Rolling" },
  { emoji: "😍", codepoint: "1f60d", label: "Smitten" },
  { emoji: "🤯", codepoint: "1f92f", label: "Mind blown" },
  { emoji: "😱", codepoint: "1f631", label: "Scream" },
  { emoji: "🥳", codepoint: "1f973", label: "Celebrate" },
  { emoji: "🙌", codepoint: "1f64c", label: "Hands up" },
  { emoji: "💯", codepoint: "1f4af", label: "Hundred" },
  { emoji: "❤️", codepoint: "2764_fe0f", label: "Heart" },
  { emoji: "👀", codepoint: "1f440", label: "Watching" },
  { emoji: "😭", codepoint: "1f62d", label: "Sobbing" },
  { emoji: "💀", codepoint: "1f480", label: "Dead" },
  { emoji: "😴", codepoint: "1f634", label: "Snooze" },
  { emoji: "🤡", codepoint: "1f921", label: "Clown" },
  { emoji: "🫠", codepoint: "1fae0", label: "Melting" },
];
