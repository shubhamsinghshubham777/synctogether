"use client";

import { useRef } from "react";
import Image from "next/image";
import {
  Play,
  Pause,
  Mic,
  MicOff,
  Video,
  VideoOff,
  Smile,
  MessageSquare,
  MoreHorizontal,
  Crown,
  X,
  Send,
  Loader2,
} from "lucide-react";
import { RoomSimActions, RoomSimState } from "./types";
import { kReactions } from "@/lib/reactions";

function randomBundledReaction() {
  return kReactions[Math.floor(Math.random() * kReactions.length)].emoji;
}

export type FrameFidelity = "full" | "reduced";

export interface RoomFrameIdentity {
  roomName: string;
  roomCode: string;
  osChrome: "macos" | "windows";
}

export interface RoomFrameProps {
  state: RoomSimState;
  actions?: RoomSimActions; // omitted => non-interactive frame
  /** Seconds this frame lags (negative) or leads (positive) the canonical clock. */
  offsetSec: number;
  fidelity: FrameFidelity;
  identity: RoomFrameIdentity;
  /** Lets the parent drive this frame's film playback (offsets, drift correction). */
  videoRef?: React.Ref<HTMLVideoElement>;
  /** Forces the 480p encode into a full-fidelity frame - viewports below 1024px. */
  lowResVideo?: boolean;
  /** Renders the poster alone: reduced motion, Save-Data, or a rejected play(). */
  posterOnly?: boolean;
  /** HUD readout - shown top-center, derived from offsetSec, announced once per change. */
  showHud?: boolean;
  /** Small floating caption bubble, e.g. "wait what just happened??" */
  caption?: string;
  /** Frame B shows a buffering spinner while desynced. */
  showBuffering?: boolean;
  /** One-shot lock-pulse ring, played on entering sync. */
  pulseLock?: boolean;
  priority?: boolean;
  className?: string;
}

const FILM_POSTER = "/film/drift-poster.avif";

function formatTime(sec: number) {
  const hrs = Math.floor(sec / 3600);
  const mins = Math.floor((sec % 3600) / 60);
  const secs = Math.floor(sec % 60);
  if (hrs > 0) {
    return `${hrs}:${mins.toString().padStart(2, "0")}:${secs.toString().padStart(2, "0")}`;
  }
  return `${mins.toString().padStart(2, "0")}:${secs.toString().padStart(2, "0")}`;
}

export function RoomFrame({
  state,
  actions,
  offsetSec,
  fidelity,
  identity,
  videoRef,
  lowResVideo,
  posterOnly,
  showHud = true,
  caption,
  showBuffering,
  pulseLock,
  priority,
  className = "",
}: RoomFrameProps) {
  const interactive = Boolean(actions);
  const scrubberRef = useRef<HTMLDivElement>(null);
  const hoverChipRef = useRef<HTMLDivElement>(null);

  // H.264 only, and one source with no fallback chain: three of these decode at once,
  // and H.264 is the one codec every device decodes in hardware. AV1/VP9 were measured
  // on this clip and gave no size win - a 9s denoised 960x540 clip gives them nothing.
  const filmSrc = fidelity === "full" && !lowResVideo ? "/film/drift-960.mp4" : "/film/drift-480.mp4";
  const progressPercent = (state.clockSec / state.durationSec) * 100;
  const hud =
    showHud && Math.abs(offsetSec) < 0.05
      ? { label: "+0ms", tone: "green" as const }
      : showHud
        ? { label: `${offsetSec > 0 ? "+" : ""}${offsetSec.toFixed(1)}s`, tone: "red" as const }
        : undefined;

  const handleScrubberMove = (e: React.MouseEvent<HTMLDivElement>) => {
    if (!scrubberRef.current || !hoverChipRef.current) return;
    const rect = scrubberRef.current.getBoundingClientRect();
    const x = Math.max(0, Math.min(rect.width, e.clientX - rect.left));
    const pct = x / rect.width;
    const chip = hoverChipRef.current;
    chip.style.left = `${pct * 100}%`;
    chip.textContent = formatTime(Math.round(pct * state.durationSec));
    chip.style.opacity = "1";
  };

  const handleScrubberLeave = () => {
    if (hoverChipRef.current) hoverChipRef.current.style.opacity = "0";
  };

  const handleScrubberClick = (e: React.MouseEvent<HTMLDivElement>) => {
    if (!scrubberRef.current || !actions) return;
    const rect = scrubberRef.current.getBoundingClientRect();
    const x = Math.max(0, Math.min(rect.width, e.clientX - rect.left));
    actions.seekTo((x / rect.width) * state.durationSec);
  };

  const synced = Math.abs(offsetSec) < 0.05;

  return (
    <div
      className={`relative rounded-[6px] overflow-hidden border border-rail flex flex-col shadow-2xl select-none text-left bg-booth ${className}`}
      aria-hidden={!interactive}
    >
      {pulseLock && (
        <div className="pointer-events-none absolute inset-0 z-40 rounded-[6px] ring-2 ring-cue/70 animate-lock-pulse" />
      )}

      {/* Titlebar */}
      <div className="bg-seat px-3 py-2 border-b border-rail/60 flex items-center shrink-0">
        {identity.osChrome === "macos" ? (
          <div className="flex items-center gap-1.5">
            <div className="w-2.5 h-2.5 rounded-full bg-[#FF5F56] border border-black/20" />
            <div className="w-2.5 h-2.5 rounded-full bg-[#FFBD2E] border border-black/20" />
            <div className="w-2.5 h-2.5 rounded-full bg-[#27C93F] border border-black/20" />
          </div>
        ) : (
          <div className="flex-1" />
        )}
        <span className="text-[11px] font-medium text-screen/70 ml-2">SyncTogether</span>
      </div>

      {/* The app's theatre layout: top strip, picture, flat bar under it. */}
      <div className="relative w-full aspect-[16/11] sm:aspect-[16/10.5] overflow-hidden flex flex-col">
        {/* Top strip */}
        <div className="relative z-10 shrink-0 h-8 sm:h-10 px-2.5 sm:px-3.5 flex items-center gap-2 sm:gap-3 border-b border-aisle bg-booth">
          <span className="text-[11px] sm:text-[13px] font-semibold text-screen font-[family-name:var(--font-display)] tracking-tight truncate">
            {identity.roomName}
          </span>
          <span className="bg-screen text-booth rounded-[2px] px-1.5 py-px text-[9px] sm:text-[10px] font-mono font-semibold tracking-[0.12em]">
            {identity.roomCode}
          </span>
          <span className="flex items-center gap-1.5 font-mono text-[9px] sm:text-[10px] tracking-[0.12em] text-screen/70">
            <span
              className={`w-1.5 h-1.5 rounded-full ${synced ? "bg-beam-400 shadow-[0_0_8px_#FFB23F]" : "border border-beam-400"}`}
            />
            {fidelity === "full" && (synced ? "IN SYNC" : "CATCHING UP")}
          </span>
          <div className="flex-1" />
          {fidelity === "full" && (
            <span className="hidden sm:inline font-mono text-[10px] tracking-[0.12em] text-screen/55">02:03</span>
          )}
          {fidelity === "full" && interactive && actions && (
            <div className="flex items-center gap-1">
              <button
                onClick={() => actions.setChatOpen(!state.chatOpen)}
                title="Toggle room chat"
                className={`w-7 h-7 rounded-[4px] border flex items-center justify-center transition-colors cursor-pointer ${
                  state.chatOpen ? "border-beam-400 text-beam-400" : "border-rail text-screen/70 hover:text-screen"
                }`}
              >
                <MessageSquare className="w-3.5 h-3.5" />
              </button>
              <button
                title="More options"
                className="w-7 h-7 rounded-[4px] text-screen/70 hover:text-screen flex items-center justify-center cursor-pointer"
              >
                <MoreHorizontal className="w-4 h-4" />
              </button>
            </div>
          )}
        </div>

        <div className="relative flex-1 flex min-h-0">
          {/* Picture */}
          <div className="relative flex-1 bg-black overflow-hidden">
            <div className="absolute inset-0 z-0">
              {posterOnly ? (
                <Image
                  src={FILM_POSTER}
                  alt=""
                  fill
                  priority={priority}
                  loading={priority ? undefined : "lazy"}
                  sizes="(max-width: 1024px) 100vw, 800px"
                  className="object-cover object-center"
                />
              ) : (
                <>
                  {/* The poster is the LCP element, never the video - hence preload="metadata". */}
                  {priority && <link rel="preload" as="image" href={FILM_POSTER} />}
                  <video
                    ref={videoRef}
                    src={filmSrc}
                    poster={FILM_POSTER}
                    muted
                    playsInline
                    loop
                    preload="metadata"
                    disablePictureInPicture
                    aria-hidden
                    tabIndex={-1}
                    className="absolute inset-0 w-full h-full object-cover object-center"
                  />
                </>
              )}
            </div>

            {hud && (
              <div
                aria-live="polite"
                className={`absolute top-2.5 left-1/2 -translate-x-1/2 z-30 px-2 py-0.5 rounded-[4px] bg-seat text-[10px] font-mono font-semibold border ${
                  hud.tone === "green" ? "border-cue/60 text-cue" : "border-signal/60 text-signal"
                }`}
              >
                {hud.label}
              </div>
            )}

            {showBuffering && (
              <div className="absolute inset-0 z-30 flex items-center justify-center pointer-events-none">
                <Loader2 className="w-8 h-8 text-screen/70 animate-spin" />
              </div>
            )}

            {caption && (
              <div className="absolute bottom-3 left-1/2 -translate-x-1/2 z-30 px-3 py-1.5 rounded-[6px] bg-seat border border-rail text-[11px] text-screen/90 whitespace-nowrap">
                {caption}
              </div>
            )}

            <div className="absolute inset-0 pointer-events-none z-20 overflow-hidden">
              {state.reactions.map((r) => (
                <div
                  key={r.id}
                  style={{ left: `${r.x}%`, bottom: `${r.y}%`, transform: `rotate(${r.rotation}deg)` }}
                  className="absolute text-3xl sm:text-4xl animate-bounce transition-all duration-1000 drop-shadow-[0_4px_16px_rgba(0,0,0,0.9)]"
                >
                  {r.emoji}
                </div>
              ))}
            </div>

            {/* Facecam rail */}
            <div
              className={`absolute z-10 top-2.5 left-2.5 sm:top-3 sm:left-3 flex flex-col gap-2 transition-transform duration-300 ${
                state.camsOn ? "translate-x-0 opacity-100" : "-translate-x-4 opacity-0 pointer-events-none"
              }`}
            >
              <FacecamTile avatar="/avatars/av-02-cam.avif" name={fidelity === "full" ? "Shubham Singh" : undefined} premium />
              <FacecamTile avatar="/avatars/av-01-cam.avif" name={fidelity === "full" ? "Guest-0397" : undefined} muted />
            </div>
          </div>

          {/* Docked chat column */}
          {fidelity === "full" && state.chatOpen && actions && (
            <div className="w-44 sm:w-56 shrink-0 z-20 bg-seat border-l border-aisle flex flex-col text-left">
              <div className="flex items-center justify-between px-2.5 py-2 border-b border-aisle">
                <span className="font-mono text-[9px] tracking-[0.14em] text-screen/55">IN THE ROOM · 2</span>
                <button onClick={() => actions.setChatOpen(false)} className="text-screen/50 hover:text-screen p-0.5">
                  <X className="w-3 h-3" />
                </button>
              </div>
              <div className="flex-1 space-y-1.5 overflow-y-auto p-2.5 text-[11px]">
                {state.chatMessages.map((msg) => (
                  <div key={msg.id} className="leading-snug">
                    <div className="text-[10px] font-semibold text-screen/60">{msg.sender}</div>
                    <div className="inline-block mt-0.5 px-2 py-1 rounded-[6px] rounded-bl-[2px] bg-aisle text-screen/90">
                      {msg.text}
                    </div>
                  </div>
                ))}
              </div>
              <form
                onSubmit={(e) => {
                  e.preventDefault();
                  const input = e.currentTarget.elements.namedItem("chat") as HTMLInputElement;
                  actions.sendChat(input.value);
                  input.value = "";
                }}
                className="flex gap-1.5 p-2 border-t border-aisle"
              >
                <input
                  name="chat"
                  type="text"
                  placeholder="Say something…"
                  className="flex-1 min-w-0 h-7 bg-booth border border-rail rounded-[4px] px-2 text-[11px] text-screen placeholder-screen/40 focus:outline-none focus:border-beam-400"
                />
                <button
                  type="submit"
                  aria-label="Send message"
                  className="w-7 h-7 shrink-0 rounded-[4px] bg-beam-500 hover:bg-beam-400 text-[#1A1206] flex items-center justify-center cursor-pointer"
                >
                  <Send className="w-3 h-3" />
                </button>
              </form>
            </div>
          )}
        </div>

        {/* Flat bar under the picture */}
        <div className="relative z-10 shrink-0 bg-booth border-t border-aisle px-2.5 sm:px-3.5 py-1.5 sm:py-2 space-y-1 sm:space-y-1.5">
          <div className="flex items-center gap-2 sm:gap-3">
            <span className="text-[10px] sm:text-[11px] font-mono font-semibold text-screen min-w-[34px]">
              {formatTime(state.clockSec)}
            </span>
            <div
              ref={scrubberRef}
              onMouseMove={interactive ? handleScrubberMove : undefined}
              onMouseLeave={interactive ? handleScrubberLeave : undefined}
              onClick={interactive ? handleScrubberClick : undefined}
              className={`relative flex-1 h-1 bg-aisle rounded-[2px] ${interactive ? "cursor-pointer group" : ""}`}
            >
              <div
                ref={hoverChipRef}
                style={{ opacity: 0 }}
                className="absolute -top-6 -translate-x-1/2 px-1.5 py-0.5 rounded-[4px] bg-seat border border-rail text-[9px] font-mono text-screen pointer-events-none transition-opacity"
              />
              <div
                className="h-full bg-beam-500 shadow-[0_0_10px_rgba(255,178,63,0.6)] rounded-[2px] relative origin-left"
                style={{ transform: `scaleX(${Math.max(0, Math.min(1, progressPercent / 100))})`, width: "100%" }}
              />
            </div>
            <span className="text-[10px] sm:text-[11px] font-mono text-screen/50 min-w-[44px] text-right">
              {formatTime(state.durationSec)}
            </span>
          </div>

          <div className="flex items-center gap-1.5">
            <button
              onClick={actions?.togglePlay}
              title={state.playing ? "Pause" : "Play"}
              disabled={!interactive}
              aria-label={state.playing ? "Pause" : "Play"}
              className={`w-8 h-7 sm:w-9 sm:h-8 rounded-[4px] bg-beam-500 text-[#1A1206] flex items-center justify-center ${
                interactive ? "cursor-pointer active:scale-95 transition-transform" : ""
              }`}
            >
              {state.playing ? <Pause className="w-3.5 h-3.5 fill-current" /> : <Play className="w-3.5 h-3.5 fill-current translate-x-px" />}
            </button>
            <div className="w-px h-4 bg-rail mx-1" />
            <IconToggle
              active={state.micOn}
              onClick={actions?.toggleMic}
              on={<Mic className="w-3.5 h-3.5" />}
              off={<MicOff className="w-3.5 h-3.5" />}
              title="Toggle mic"
            />
            {fidelity === "full" && (
              <IconToggle
                active={state.camOn}
                onClick={actions?.toggleCam}
                on={<Video className="w-3.5 h-3.5" />}
                off={<VideoOff className="w-3.5 h-3.5" />}
                title="Toggle camera"
              />
            )}
            {fidelity === "full" && interactive && actions && (
              <button
                onClick={() => actions.react(randomBundledReaction())}
                title="Send reaction"
                className="p-1.5 rounded-[4px] border border-rail text-screen/60 hover:text-screen transition-colors cursor-pointer"
              >
                <Smile className="w-3.5 h-3.5" />
              </button>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

function FacecamTile({
  avatar,
  name,
  premium,
  muted,
}: {
  /** The -cam crop, which fills the tile as the camera feed itself. */
  avatar: string;
  name?: string;
  premium?: boolean;
  muted?: boolean;
}) {
  return (
    <div
      className={`w-24 sm:w-28 h-14 sm:h-16 rounded-[4px] border ${
        premium ? "border-brass" : "border-rail"
      } relative overflow-hidden bg-aisle`}
    >
      {/* Fixed 128px in every frame, so the two files decode once and the scaled-down
          secondaries reuse them rather than pulling a second srcset candidate. */}
      <Image src={avatar} alt="" fill sizes="128px" className="object-cover" />
      {/* Scrim only under the label - a full-tile wash would dull the feed it sits on. */}
      
      {premium && (
        <Crown
          className="w-3 h-3 text-amber-400 fill-amber-400 absolute top-1 left-1 drop-shadow"
          aria-label="Premium Host"
        />
      )}
      {name && (
        <span className="absolute bottom-1 left-1 px-1 rounded-[2px] bg-booth/70 text-[9px] font-semibold text-screen">
          {name}
        </span>
      )}
      <div
        className={`absolute top-1 right-1 w-3.5 h-3.5 rounded-full border flex items-center justify-center ${
          muted
            ? "bg-[#2A1714]/90 border-red-500/40 text-red-400"
            : "bg-black/50 border-white/25 text-white/85"
        }`}
      >
        {muted ? <MicOff className="w-2 h-2" /> : <Mic className="w-2 h-2" />}
      </div>
    </div>
  );
}

function IconToggle({
  active,
  onClick,
  on,
  off,
  title,
}: {
  active: boolean;
  onClick?: () => void;
  on: React.ReactNode;
  off: React.ReactNode;
  title: string;
}) {
  return (
    <button
      onClick={onClick}
      title={title}
      disabled={!onClick}
      className={`p-1.5 rounded-[4px] border transition-colors ${onClick ? "cursor-pointer" : ""} ${
        active ? "border-signal text-signal" : "border-rail text-screen/60 hover:text-screen"
      }`}
    >
      {active ? on : off}
    </button>
  );
}
