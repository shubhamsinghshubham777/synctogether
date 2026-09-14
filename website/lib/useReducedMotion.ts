"use client";
import { useMediaQuery } from "./useMediaQuery";

export function useReducedMotion(): boolean {
  // Server snapshot is false: assume motion is fine, then correct on mount.
  return useMediaQuery("(prefers-reduced-motion: reduce)");
}
