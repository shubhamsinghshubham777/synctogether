import { ArrowLeft, Compass } from "lucide-react";
import { PTButton } from "@/components/PTButton";

export default function NotFound() {
  return (
    <div className="relative min-h-[calc(100vh-5rem)] flex items-center justify-center px-4 py-16 overflow-hidden">
      {/* Ambient background glow */}
      <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[500px] h-[500px] bg-purple-600/10 rounded-full blur-3xl pointer-events-none -z-10" />

      <div className="relative max-w-lg w-full text-center space-y-6">
        <div className="inline-flex items-center justify-center w-16 h-16 rounded-2xl bg-purple-500/10 border border-purple-500/20 text-purple-300 mb-2">
          <Compass className="w-8 h-8 animate-pulse" />
        </div>

        <div className="space-y-2">
          <p className="text-xs uppercase tracking-widest text-purple-400 font-semibold font-mono">
            Error 404
          </p>
          <h1 className="text-4xl sm:text-5xl font-bold text-white tracking-tight font-[family-name:var(--font-space-grotesk)]">
            Lost in sync
          </h1>
          <p className="text-gray-400 text-sm sm:text-base max-w-md mx-auto">
            This page doesn&apos;t exist, was moved, or requires specific access privileges.
          </p>
        </div>

        <div className="flex flex-col sm:flex-row items-center justify-center gap-3 pt-2">
          <PTButton href="/" variant="primary" leftIcon={<ArrowLeft className="w-4 h-4" />}>
            Back to Home
          </PTButton>
          <PTButton href="/download" variant="secondary">
            Download App
          </PTButton>
        </div>
      </div>
    </div>
  );
}
