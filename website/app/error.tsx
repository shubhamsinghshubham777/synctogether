"use client";

import { useEffect } from "react";
import { AlertCircle, RotateCcw } from "lucide-react";
import { PTButton } from "@/components/PTButton";

export default function ErrorBoundary({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    console.error("Uncaught website error:", error);
  }, [error]);

  return (
    <div className="relative min-h-[calc(100vh-5rem)] flex items-center justify-center px-4 py-16 overflow-hidden">
      <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[500px] h-[500px] bg-red-500/10 rounded-full blur-3xl pointer-events-none -z-10" />

      <div className="relative max-w-lg w-full text-center space-y-6">
        <div className="inline-flex items-center justify-center w-16 h-16 rounded-2xl bg-red-500/10 border border-red-500/20 text-red-400 mb-2">
          <AlertCircle className="w-8 h-8" />
        </div>

        <div className="space-y-2">
          <h1 className="text-3xl sm:text-4xl font-bold text-white tracking-tight font-[family-name:var(--font-space-grotesk)]">
            Something went wrong
          </h1>
          <p className="text-gray-400 text-sm sm:text-base max-w-md mx-auto">
            An unexpected error occurred while loading this page.
          </p>
        </div>

        <div className="flex flex-col sm:flex-row items-center justify-center gap-3 pt-2">
          <PTButton onClick={() => reset()} variant="primary" leftIcon={<RotateCcw className="w-4 h-4" />}>
            Try again
          </PTButton>
          <PTButton href="/" variant="secondary">
            Back to Home
          </PTButton>
        </div>
      </div>
    </div>
  );
}
