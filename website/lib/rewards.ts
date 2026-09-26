import { createAdminClient } from "./supabase/admin.ts";

/**
 * Server-side reads for the gamification pages.
 *
 * Everything here goes through `security definer` RPCs granted to the service
 * role only - there is no anon surface on any of it, and the RPCs themselves
 * are what enforce that a profile is only published when its owner opted in.
 * A page must never reach into these tables directly.
 */

export interface RecapPerson {
  seed: string;
  name?: string | null;
  avatar?: string | null;
  handle?: string | null;
  frame?: string | null;
  premium?: boolean;
  public: boolean;
}

export interface RecapSuperlative {
  key: string;
  person: RecapPerson | null;
}

export interface Recap {
  id: string;
  v: number;
  room_name: string | null;
  seconds: number;
  peak_members: number;
  messages: number;
  reactions: number;
  top_emoji: string | null;
  modes: string[];
  facecam: boolean;
  owner: RecapPerson;
  people: RecapPerson[];
  superlatives: RecapSuperlative[];
  ended_at: string;
  created_at: string;
}

export interface LeaderboardEntry {
  rank: number;
  name: string;
  avatar: string | null;
  handle: string | null;
  frame: string | null;
  premium: boolean;
  points: number;
  streak: number;
}

export interface PublicBoard {
  open: boolean;
  period?: string;
  rows: LeaderboardEntry[];
}

export interface ProfileBadge {
  id: string;
  title: string;
  icon: string;
  grade: string;
}

export interface SeasonAward {
  season: string;
  rank: number;
}

export interface ProfileCard {
  handle: string;
  name: string;
  avatar: string | null;
  frame: string | null;
  premium: boolean;
  joined: string;
  streak: number;
  longest_streak: number;
  hours: number;
  sessions: number;
  co_watchers: number;
  points_week: number;
  badges: ProfileBadge[];
  seasons: SeasonAward[];
}

export interface WrappedCard {
  year: number;
  handle: string;
  name: string;
  avatar: string | null;
  seconds: number;
  days: number;
  points: number;
  longest_streak: number;
  top_co_watchers: { name: string | null; avatar: string | null; seed: string; hours: number }[];
  badges: ProfileBadge[];
}

async function rpc<T>(name: string, params: Record<string, unknown>): Promise<T | null> {
  try {
    const supabase = createAdminClient();
    const { data, error } = await supabase.rpc(name, params);
    if (error) {
      console.warn(`rewards rpc ${name} failed:`, error.message);
      return null;
    }
    return (data ?? null) as T | null;
  } catch (err) {
    console.warn(`rewards rpc ${name} threw:`, err);
    return null;
  }
}

export const getRecap = (id: string) => rpc<Recap>("public_recap", { p_id: id });

export const getProfileCard = (handle: string) =>
  rpc<ProfileCard>("public_profile_card", { p_handle: handle });

export const getWrapped = (handle: string, year: number) =>
  rpc<WrappedCard>("public_wrapped", { p_handle: handle, p_year: year });

export async function getPublicBoard(period = "week", limit = 50): Promise<PublicBoard> {
  const board = await rpc<PublicBoard>("public_leaderboard", {
    p_period: period,
    p_limit: limit,
  });
  return board ?? { open: false, rows: [] };
}

/**
 * Room codes are six characters from a deliberately unambiguous alphabet - no
 * 0/O and no 1/I, matching `create_room`. Anything else is not a code, and a
 * page that accepts one would be inviting people into a 404.
 */
const CODE_ALPHABET = /^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$/;

export function normalizeRoomCode(raw: string): string | null {
  const code = raw.trim().toUpperCase();
  return CODE_ALPHABET.test(code) ? code : null;
}

/** "4h 12m" / "38m" - the same shape the app uses, so a share reads the same. */
export function formatWatchTime(seconds: number): string {
  const totalMinutes = Math.floor(seconds / 60);
  if (totalMinutes < 1) return "under a minute";
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  if (hours === 0) return `${minutes}m`;
  if (minutes === 0) return `${hours}h`;
  return `${hours}h ${minutes}m`;
}

export function formatPoints(points: number): string {
  if (points < 1000) return `${points}`;
  if (points < 1000000) {
    const thousands = points / 1000;
    return `${thousands < 10 ? thousands.toFixed(1) : Math.round(thousands)}k`;
  }
  return `${(points / 1000000).toFixed(1)}M`;
}

/** "May 2026" from 'YYYY-MM'; falls back to the raw id rather than throwing. */
export function seasonMonthLabel(season: string): string {
  const [yearRaw, monthRaw] = season.split("-");
  const year = Number.parseInt(yearRaw ?? "", 10);
  const month = Number.parseInt(monthRaw ?? "", 10);
  if (!Number.isFinite(year) || !Number.isFinite(month) || month < 1 || month > 12) {
    return season;
  }
  const names = [
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
  ];
  return `${names[month - 1]} ${year}`;
}

export function seasonRankLabel(rank: number): string {
  if (rank === 1) return "Season winner";
  if (rank === 2) return "Season runner-up";
  return "Season third";
}

export const SUPERLATIVE_TITLES: Record<string, string> = {
  reactions: "Reaction Machine",
  chat: "Chatterbox",
  pauser: "The Pauser",
  camera: "On Camera",
  ride_or_die: "Ride or Die",
  steady: "Rock Solid",
  night_owl: "Night Owl",
  first_in: "First In",
  host: "Host With The Most",
};

/**
 * Gradient for an avatar with no photo. Mirrors `PTColors.avatarGradients`, and
 * is keyed on the hashed seed the RPC publishes rather than on a user id -
 * public pages carry no account identifiers.
 */
const AVATAR_GRADIENTS: [string, string][] = [
  // Mirrors PTColors.avatarGradients in lib/ui/pt_theme.dart: muted seat
  // colours in two close shades, so avatars read flat on the booth.
  ["#8468FF", "#7A5CFF"],
  ["#379577", "#2E8A6E"],
  ["#C25038", "#B8462E"],
  ["#4A79BA", "#3F6FB0"],
  ["#B0782E", "#A56E26"],
  ["#A8527A", "#9D4870"],
  ["#5E8A3E", "#548036"],
  ["#6F6258", "#65584F"],
];

export function gradientForSeed(seed: string): [string, string] {
  let hash = 0;
  for (let i = 0; i < seed.length; i++) {
    hash = (hash * 31 + seed.charCodeAt(i)) >>> 0;
  }
  return AVATAR_GRADIENTS[hash % AVATAR_GRADIENTS.length];
}

/** What a public page is allowed to call somebody who never opted in. */
export function displayNameFor(person: RecapPerson | null | undefined): string {
  if (!person) return "Someone";
  return person.public && person.name ? person.name : "A friend";
}
