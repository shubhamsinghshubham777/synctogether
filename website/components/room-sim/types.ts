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
  micOn: boolean;
  camOn: boolean;
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
  toggleMic(): void;
  toggleCam(): void;
  setVolume(v: number): void;
  toggleMuted(): void;
}

export const REACTION_LIFETIME_MS = 2200;
export const REACTION_CAP = 14;
export const SIM_DURATION_SEC = 8673; // 02:24:33
