"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import {
  ChatMessage,
  REACTION_CAP,
  REACTION_LIFETIME_MS,
  ReactionParticle,
  RoomSimActions,
  RoomSimState,
  SIM_DURATION_SEC,
} from "./types";

const INITIAL_CHAT: ChatMessage[] = [
  { id: 1, sender: "Maya", text: "That sound design was unreal 🤯", color: "text-purple-300" },
  { id: 2, sender: "Guest-0397", text: "Wait, don't skip the credits!!", color: "text-pink-300" },
];

export function useRoomSim(opts: { active: boolean }): RoomSimState & { actions: RoomSimActions } {
  const [playing, setPlaying] = useState(true);
  const [clockSec, setClockSec] = useState(35);
  const [reactions, setReactions] = useState<ReactionParticle[]>([]);
  const [chatMessages, setChatMessages] = useState<ChatMessage[]>(INITIAL_CHAT);
  const [chatOpen, setChatOpen] = useState(false);
  const [camsOn, setCamsOn] = useState(true);
  const [micOn, setMicOn] = useState(false);
  const [camOn, setCamOn] = useState(false);
  const [volume, setVolumeState] = useState(0.85);
  const [muted, setMuted] = useState(false);

  const reactionCounter = useRef(0);
  const reactionTimers = useRef<Set<ReturnType<typeof setTimeout>>>(new Set());

  // Canonical clock - ticks at 1 Hz, only while the hero is actually on screen.
  useEffect(() => {
    if (!opts.active || !playing) return;
    const interval = setInterval(() => {
      setClockSec((prev) => (prev >= SIM_DURATION_SEC ? 0 : prev + 1));
    }, 1000);
    return () => clearInterval(interval);
  }, [opts.active, playing]);

  // Reaction lifetime timers must be cleared on unmount.
  useEffect(() => {
    const timers = reactionTimers.current;
    return () => {
      timers.forEach(clearTimeout);
      timers.clear();
    };
  }, []);

  const react = useCallback((emoji: string) => {
    reactionCounter.current += 1;
    const count = reactionCounter.current;
    const particle: ReactionParticle = {
      id: count,
      emoji,
      x: 35 + ((count * 19) % 35),
      y: 65 + ((count * 11) % 15),
      rotation: ((count * 23) % 40) - 20,
    };
    setReactions((prev) => [...prev.slice(-(REACTION_CAP - 1)), particle]);
    const timer = setTimeout(() => {
      setReactions((prev) => prev.filter((r) => r.id !== particle.id));
      reactionTimers.current.delete(timer);
    }, REACTION_LIFETIME_MS);
    reactionTimers.current.add(timer);
  }, []);

  const seekTo = useCallback((sec: number) => {
    setClockSec(Math.max(0, Math.min(SIM_DURATION_SEC, Math.round(sec))));
  }, []);

  const skip = useCallback(
    (deltaSec: number) => {
      setClockSec((prev) => Math.max(0, Math.min(SIM_DURATION_SEC, prev + deltaSec)));
    },
    [],
  );

  const sendChat = useCallback((text: string) => {
    const trimmed = text.trim();
    if (!trimmed) return;
    setChatMessages((prev) => [
      ...prev,
      { id: Date.now(), sender: "You", text: trimmed, color: "text-purple-400 font-semibold" },
    ]);
  }, []);

  const actions: RoomSimActions = {
    togglePlay: () => setPlaying((p) => !p),
    seekTo,
    skip,
    react,
    sendChat,
    setChatOpen,
    toggleCams: () => setCamsOn((v) => !v),
    toggleMic: () => setMicOn((v) => !v),
    toggleCam: () => setCamOn((v) => !v),
    setVolume: (v: number) => setVolumeState(v),
    toggleMuted: () => setMuted((v) => !v),
  };

  return {
    playing,
    clockSec,
    durationSec: SIM_DURATION_SEC,
    reactions,
    chatMessages,
    chatOpen,
    camsOn,
    micOn,
    camOn,
    volume,
    muted,
    actions,
  };
}
