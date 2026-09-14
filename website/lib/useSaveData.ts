"use client";
import { useSyncExternalStore } from "react";

type SaveDataConnection = EventTarget & { saveData?: boolean };

function connection(): SaveDataConnection | undefined {
  if (typeof navigator === "undefined") return undefined;
  return (navigator as Navigator & { connection?: SaveDataConnection }).connection;
}

function subscribe(cb: () => void) {
  const conn = connection();
  if (!conn) return () => {};
  conn.addEventListener("change", cb);
  return () => conn.removeEventListener("change", cb);
}

/**
 * Whether the viewer asked for less data. Read through an external store rather than
 * an effect so the server snapshot is honest (false) and the client never has to
 * cascade a render to correct it.
 */
export function useSaveData(): boolean {
  return useSyncExternalStore(
    subscribe,
    () => connection()?.saveData === true,
    () => false,
  );
}
