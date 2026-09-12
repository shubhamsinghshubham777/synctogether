import Link from "next/link";
import { SyncTogetherIcon } from "./Icons";

interface LogoProps {
  className?: string;
  size?: "sm" | "md" | "lg" | "xl";
  showText?: boolean;
  asLink?: boolean;
}

export function Logo({
  className = "",
  size = "md",
  showText = true,
  asLink = true,
}: LogoProps) {
  const sizeMap = {
    sm: { icon: "w-7 h-7", text: "text-lg" },
    md: { icon: "w-9 h-9", text: "text-xl" },
    lg: { icon: "w-12 h-12", text: "text-2xl" },
    xl: { icon: "w-16 h-16", text: "text-3xl" },
  };

  const s = sizeMap[size];

  const content = (
    <>
      {/* Brand Icon */}
      <div
        className={`${s.icon} shrink-0 flex items-center justify-center drop-shadow-[0_4px_16px_rgba(139,92,246,0.35)] group-hover:drop-shadow-[0_4px_22px_rgba(139,92,246,0.55)] transition-all duration-200 group-hover:scale-105`}
      >
        <SyncTogetherIcon className="w-full h-full" />
      </div>

      {/* Brand Name */}
      {showText && (
        <div className="flex flex-col">
          <span
            className={`${s.text} font-bold tracking-tight text-white font-[family-name:var(--font-space-grotesk)]`}
          >
            Sync<span className="text-gradient-accent">Together</span>
          </span>
        </div>
      )}
    </>
  );

  if (!asLink) {
    return (
      <div className={`inline-flex items-center gap-2.5 group ${className}`}>
        {content}
      </div>
    );
  }

  return (
    <Link
      href="/"
      className={`inline-flex items-center gap-2.5 group transition-transform duration-200 active:scale-95 ${className}`}
    >
      {content}
    </Link>
  );
}

export { SyncTogetherIcon };

