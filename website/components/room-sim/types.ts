export interface ReactionParticle {
  id: number;
  emoji: string;
  x: number; // percent from left
  y: number; // percent from bottom
  rotation: number; // degrees
}

export interface ChatMessage {
  id: number;
  sender: string;
  text: string;
  color: string;
}

export interface RoomSimState {
  playing: boolean;
  /** Canonical room clock, seconds. Frames apply their own offset to this. */
  clockSec: number;
  durationSec: number; // 8673 (02:24:33)
  reactions: ReactionParticle[];
  chatMessages: ChatMessage[];
  chatOpen: boolean;
  camsOn: boolean;
  volume: number;
  muted: boolean;
}

export interface RoomSimActions {
  togglePlay(): void;
  seekTo(sec: number): void;
  skip(deltaSec: number): void;
  react(emoji: string): void;
  sendChat(text: string): void;
  setChatOpen(open: boolean): void;
  toggleCams(): void;
  setVolume(v: number): void;
  toggleMuted(): void;
}

export const REACTION_LIFETIME_MS = 2200;
export const REACTION_CAP = 14;
export const SIM_DURATION_SEC = 8673; // 02:24:33

/** The three people in the demo room. Each window is one of them. */
export type PersonId = "sam" | "guest" | "maya";

export interface PersonInfo {
  /** The -cam crop, which fills the tile as the camera feed itself. */
  avatar: string;
  /** The label full-fidelity tiles carry. */
  name: string;
  initial: string;
  premium?: boolean;
}

export const PEOPLE: Record<PersonId, PersonInfo> = {
  sam: { avatar: "/avatars/av-02-cam.avif", name: "Sam Rivera", initial: "S", premium: true },
  guest: { avatar: "/avatars/av-01-cam.avif", name: "Guest-0397", initial: "G" },
  maya: { avatar: "/avatars/av-04-cam.avif", name: "Maya", initial: "M" },
};

/** Each window lists its own owner first, then the others (as the app does). */
export const TILE_ORDER: Record<PersonId, [PersonId, PersonId, PersonId]> = {
  sam: ["sam", "guest", "maya"],
  guest: ["guest", "sam", "maya"],
  maya: ["maya", "guest", "sam"],
};

/** What every window shows for everyone: one source of truth, so a toggle shows up on all tiles. */
export type Facecams = Record<PersonId, { mic: boolean; cam: boolean }>;

export const INITIAL_FACECAMS: Facecams = {
  sam: { mic: true, cam: true },
  guest: { mic: false, cam: true },
  maya: { mic: true, cam: true },
};
