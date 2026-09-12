"use client";

import "./globals.css";
import { AlertCircle, RotateCcw } from "lucide-react";

export default function GlobalError({
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return (
    <html lang="en" className="dark" style={{ colorScheme: "dark" }}>
      <head>
        <meta name="color-scheme" content="dark" />
        <meta name="theme-color" content="#08070C" />
      </head>
      <body className="min-h-screen flex items-center justify-center bg-[#08070C] text-gray-100 antialiased p-4">
        <div className="max-w-md w-full text-center space-y-6">
          <div className="inline-flex items-center justify-center w-16 h-16 rounded-2xl bg-red-500/10 border border-red-500/20 text-red-400">
            <AlertCircle className="w-8 h-8" />
          </div>
          <div className="space-y-2">
            <h1 className="text-3xl font-bold text-white tracking-tight">
              Application Error
            </h1>
            <p className="text-gray-400 text-sm">
              A critical error prevented this page from loading.
            </p>
          </div>
          <button
            onClick={() => reset()}
            className="inline-flex items-center gap-2 px-5 py-2.5 rounded-xl bg-purple-600 hover:bg-purple-500 text-white font-semibold text-sm transition-all"
          >
            <RotateCcw className="w-4 h-4" />
            Try again
          </button>
        </div>
      </body>
    </html>
  );
}
