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
  MoreVertical,
  Crown,
  X,
  Send,
  Loader2,
  Timer,
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

  const surface =
    fidelity === "full" ? "backdrop-blur-xl bg-[#141022]/80" : "bg-[#141022]/92";

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

  return (
    <div
      className={`relative rounded-xl md:rounded-2xl overflow-hidden border border-white/10 flex flex-col shadow-2xl select-none text-left bg-[#0B0A14] ${className}`}
      aria-hidden={!interactive}
    >
      {pulseLock && (
        <div className="pointer-events-none absolute inset-0 z-40 rounded-xl md:rounded-2xl ring-2 ring-emerald-400/70 animate-lock-pulse" />
      )}

      {/* Titlebar */}
      <div className="bg-[#0e0c1a] px-3 py-2 border-b border-white/5 flex items-center shrink-0">
        {identity.osChrome === "macos" ? (
          <div className="flex items-center gap-1.5">
            <div className="w-2.5 h-2.5 rounded-full bg-[#FF5F56] border border-black/20" />
            <div className="w-2.5 h-2.5 rounded-full bg-[#FFBD2E] border border-black/20" />
            <div className="w-2.5 h-2.5 rounded-full bg-[#27C93F] border border-black/20" />
          </div>
        ) : (
          <div className="flex-1" />
        )}
        <span className="text-[11px] font-medium text-gray-300 ml-2 font-[family-name:var(--font-outfit)]">
          SyncTogether
        </span>
      </div>

      {/* Canvas */}
      <div className="relative w-full aspect-[16/10] sm:aspect-[16/9] overflow-hidden bg-black flex flex-col justify-between">
        <div className="absolute inset-0 z-0">
          {posterOnly ? (
            <Image
              src={FILM_POSTER}
              alt=""
              fill
              priority={priority}
              loading={priority ? undefined : "lazy"}
              sizes="(max-width: 1024px) 100vw, 800px"
              className="object-cover object-center brightness-90 contrast-105"
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
                className="absolute inset-0 w-full h-full object-cover object-center brightness-90 contrast-105"
              />
            </>
          )}
          <div className="absolute inset-0 bg-gradient-to-t from-black/85 via-black/10 to-black/60 pointer-events-none" />
          <div className="absolute inset-0 bg-gradient-to-r from-black/40 via-transparent to-black/40 pointer-events-none" />
        </div>

        {/* HUD readout */}
        {hud && (
          <div
            aria-live="polite"
            className={`absolute top-2 left-1/2 -translate-x-1/2 z-30 px-2.5 py-1 rounded-full text-[11px] font-mono font-semibold border backdrop-blur-md ${
              hud.tone === "green"
                ? "bg-emerald-500/15 border-emerald-400/40 text-emerald-300"
                : "bg-red-500/15 border-red-400/40 text-red-300"
            }`}
          >
            {hud.label}
          </div>
        )}

        {/* Buffering spinner */}
        {showBuffering && (
          <div className="absolute inset-0 z-30 flex items-center justify-center pointer-events-none">
            <Loader2 className="w-8 h-8 text-white/70 animate-spin" />
          </div>
        )}

        {/* Caption bubble */}
        {caption && (
          <div className="absolute bottom-20 sm:bottom-24 left-1/2 -translate-x-1/2 z-30 px-3 py-1.5 rounded-full bg-[#141022]/90 border border-white/15 text-[11px] text-gray-200 whitespace-nowrap shadow-xl">
            {caption}
          </div>
        )}

        {/* Reactions overlay */}
        <div className="absolute inset-0 pointer-events-none z-20 overflow-hidden">
          {state.reactions.map((r) => (
            <div
              key={r.id}
              style={{
                left: `${r.x}%`,
                bottom: `${r.y}%`,
                transform: `rotate(${r.rotation}deg)`,
              }}
              className="absolute text-3xl sm:text-4xl animate-bounce transition-all duration-1000 drop-shadow-[0_4px_16px_rgba(0,0,0,0.9)]"
            >
              {r.emoji}
            </div>
          ))}
        </div>

        {/* Top bar */}
        <div className="relative z-10 p-2.5 sm:p-3.5 flex items-start justify-between gap-2">
          <div
            className={`${surface} border border-white/10 rounded-full px-2.5 py-1 sm:px-3 sm:py-1.5 shadow-xl flex items-center gap-1.5 sm:gap-2.5`}
          >
            <span className="text-[11px] sm:text-xs font-semibold text-white font-[family-name:var(--font-space-grotesk)] tracking-tight">
              {identity.roomName}
            </span>
            <span className="bg-[#A78BFA]/15 border border-[#A78BFA]/35 rounded-full px-2 py-0.5 text-[10px] font-mono font-medium text-[#C9B8FF] tracking-wider">
              {identity.roomCode}
            </span>
            {fidelity === "full" && (
              <span className="flex items-center gap-1 text-[10px] font-mono font-medium text-amber-300/90">
                <Timer className="w-3 h-3 text-amber-400" />
                02:03 left
              </span>
            )}
          </div>

          {fidelity === "full" && interactive && actions && (
            <div className="flex items-center gap-1.5">
              <button
                onClick={() => actions.setChatOpen(!state.chatOpen)}
                title="Toggle room chat"
                className={`w-8 h-8 rounded-full ${surface} border flex items-center justify-center transition-all cursor-pointer relative ${
                  state.chatOpen
                    ? "border-purple-400 bg-purple-600/90 text-white"
                    : "border-white/10 text-gray-300 hover:text-white"
                }`}
              >
                <MessageSquare className="w-4 h-4" />
              </button>
              <button
                title="More options"
                className={`w-8 h-8 rounded-full ${surface} border border-white/10 text-gray-300 hover:text-white flex items-center justify-center transition-all cursor-pointer`}
              >
                <MoreVertical className="w-4 h-4" />
              </button>
            </div>
          )}
        </div>

        {/* Facecam rail */}
        <div className="relative z-10 px-2.5 sm:px-3.5 flex-1 flex flex-col justify-start">
          <div
            className={`transition-transform duration-300 flex flex-col gap-2 ${
              state.camsOn ? "translate-x-0 opacity-100" : "-translate-x-4 opacity-0 pointer-events-none"
            }`}
          >
            <FacecamTile
              avatar="/avatars/av-02-cam.avif"
              name={fidelity === "full" ? "Shubham Singh" : undefined}
              premium
            />
            <FacecamTile
              avatar="/avatars/av-01-cam.avif"
              name={fidelity === "full" ? "Guest-0397" : undefined}
              muted
            />
          </div>
        </div>

        {/* Chat overlay */}
        {fidelity === "full" && state.chatOpen && actions && (
          <div className="absolute top-14 right-3 w-64 sm:w-72 z-20 backdrop-blur-2xl bg-[#141022]/95 border border-purple-400/30 rounded-2xl p-3 shadow-2xl space-y-2.5 text-left">
            <div className="flex items-center justify-between border-b border-white/10 pb-1.5">
              <div className="flex items-center gap-1.5 text-xs font-semibold text-white">
                <MessageSquare className="w-3.5 h-3.5 text-purple-400" />
                <span>Room Chat</span>
              </div>
              <button
                onClick={() => actions.setChatOpen(false)}
                className="text-gray-400 hover:text-white p-1 rounded transition-colors"
              >
                <X className="w-3.5 h-3.5" />
              </button>
            </div>
            <div className="space-y-1.5 max-h-40 overflow-y-auto text-xs pr-1">
              {state.chatMessages.map((msg) => (
                <div key={msg.id} className="p-1.5 rounded-lg bg-white/5 border border-white/5 text-gray-200 leading-snug">
                  <span className={`font-semibold ${msg.color}`}>{msg.sender}: </span>
                  <span>{msg.text}</span>
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
              className="flex gap-1.5 pt-1"
            >
              <input
                name="chat"
                type="text"
                placeholder="Send a chat message..."
                className="flex-1 h-8 bg-black/40 border border-white/10 rounded-lg px-2.5 text-xs text-white placeholder-gray-500 focus:outline-none focus:border-purple-400"
              />
              <button
                type="submit"
                aria-label="Send message"
                className="w-8 h-8 shrink-0 rounded-lg bg-purple-600 hover:bg-purple-500 text-white flex items-center justify-center transition-colors cursor-pointer"
              >
                <Send className="w-3.5 h-3.5" />
              </button>
            </form>
          </div>
        )}

        {/* Bottom control dock */}
        <div className="relative z-10 p-2.5 sm:p-3.5 flex flex-col items-center">
          <div
            className={`w-full max-w-3xl ${surface} border border-white/10 rounded-xl md:rounded-2xl px-3 sm:px-4 py-2 sm:py-2.5 shadow-2xl space-y-1.5 sm:space-y-2`}
          >
            <div className="flex items-center gap-2 sm:gap-3">
              <span className="text-[11px] sm:text-xs font-mono font-medium text-white min-w-[34px]">
                {formatTime(state.clockSec)}
              </span>
              <div
                ref={scrubberRef}
                onMouseMove={interactive ? handleScrubberMove : undefined}
                onMouseLeave={interactive ? handleScrubberLeave : undefined}
                onClick={interactive ? handleScrubberClick : undefined}
                className={`relative flex-1 h-1.5 bg-white/15 rounded-full ${interactive ? "cursor-pointer group" : ""}`}
              >
                <div
                  ref={hoverChipRef}
                  style={{ opacity: 0 }}
                  className="absolute -top-6 -translate-x-1/2 px-1.5 py-0.5 rounded bg-[#161226] border border-white/20 text-[9px] font-mono text-purple-200 shadow-xl pointer-events-none transition-opacity"
                />
                <div
                  className="h-full bg-gradient-to-r from-[#8B5CF6] via-[#A855F7] to-[#C084FC] rounded-full relative origin-left"
                  style={{ transform: `scaleX(${Math.max(0, Math.min(1, progressPercent / 100))})`, width: "100%" }}
                >
                  <div className="absolute right-0 top-1/2 -translate-y-1/2 w-2.5 h-2.5 bg-white rounded-full shadow-[0_0_8px_rgba(255,255,255,0.9)]" />
                </div>
              </div>
              <span className="text-[11px] sm:text-xs font-mono text-white/50 min-w-[44px] text-right">
                {formatTime(state.durationSec)}
              </span>
            </div>

            <div className="flex items-center justify-between">
              <div className="flex items-center gap-1">
                <IconToggle
                  active={state.micOn}
                  onClick={actions?.toggleMic}
                  on={<Mic className="w-4 h-4" />}
                  off={<MicOff className="w-4 h-4" />}
                  title="Toggle mic"
                />
                {fidelity === "full" && (
                  <IconToggle
                    active={state.camOn}
                    onClick={actions?.toggleCam}
                    on={<Video className="w-4 h-4" />}
                    off={<VideoOff className="w-4 h-4" />}
                    title="Toggle camera"
                  />
                )}
              </div>

              <button
                onClick={actions?.togglePlay}
                title={state.playing ? "Pause" : "Play"}
                disabled={!interactive}
                aria-label={state.playing ? "Pause" : "Play"}
                className={`w-9 h-9 sm:w-10 sm:h-10 rounded-full bg-gradient-to-tr from-[#8B5CF6] via-[#9333EA] to-[#A855F7] text-white flex items-center justify-center shadow-[0_0_18px_rgba(168,85,247,0.55)] ${
                  interactive ? "cursor-pointer hover:scale-105 active:scale-95 transition-transform" : ""
                }`}
              >
                {state.playing ? <Pause className="w-4 h-4 fill-current" /> : <Play className="w-4 h-4 fill-current translate-x-0.5" />}
              </button>

              <div className="flex items-center gap-1">
                {fidelity === "full" && interactive && actions && (
                  <button
                    onClick={() => actions.react(randomBundledReaction())}
                    title="Send reaction"
                    className="p-1.5 rounded-xl text-gray-400 hover:text-white hover:bg-white/10 transition-all cursor-pointer"
                  >
                    <Smile className="w-4 h-4" />
                  </button>
                )}
              </div>
            </div>
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
      className={`w-28 sm:w-32 h-16 sm:h-[4.5rem] rounded-xl border ${
        premium ? "border-[#C4A8FF]" : "border-white/10"
      } relative overflow-hidden bg-[#1A1430]`}
    >
      {/* Fixed 128px in every frame, so the two files decode once and the scaled-down
          secondaries reuse them rather than pulling a second srcset candidate. */}
      <Image src={avatar} alt="" fill sizes="128px" className="object-cover" />
      {/* Scrim only under the label - a full-tile wash would dull the feed it sits on. */}
      <div className="absolute inset-x-0 bottom-0 h-1/2 bg-gradient-to-t from-black/75 to-transparent" />

      {premium && (
        <Crown
          className="w-3 h-3 text-amber-400 fill-amber-400 absolute top-1 left-1 drop-shadow"
          aria-label="Premium Host"
        />
      )}
      {name && (
        <span className="absolute bottom-1 left-1.5 text-[9px] font-medium text-white/90 drop-shadow">
          {name}
        </span>
      )}
      <div
        className={`absolute top-1 right-1 w-3.5 h-3.5 rounded-full border flex items-center justify-center ${
          muted
            ? "bg-[#2A1414]/90 border-red-500/40 text-red-400"
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
      className={`p-1.5 rounded-xl transition-all ${onClick ? "cursor-pointer" : ""} ${
        active ? "bg-purple-600/30 text-purple-300 border border-purple-400/40" : "text-gray-400 hover:text-white hover:bg-white/10"
      }`}
    >
      {active ? on : off}
    </button>
  );
}
