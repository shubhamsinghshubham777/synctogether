import React from "react";

interface GlassPanelProps extends React.HTMLAttributes<HTMLDivElement> {
  children: React.ReactNode;
  hoverEffect?: boolean;
  glow?: "none" | "purple" | "gold" | "cyan";
  className?: string;
}

export function GlassPanel({
  children,
  hoverEffect = false,
  glow = "none",
  className = "",
  ...props
}: GlassPanelProps) {
  const glowMap = {
    none: "",
    purple: "hover:shadow-[0_0_30px_rgba(255,178,63,0.25)] hover:border-[#FFB23F]/40",
    gold: "hover:shadow-[0_0_30px_rgba(251,191,36,0.25)] hover:border-[#FBBF24]/40",
    cyan: "hover:shadow-[0_0_30px_rgba(34,211,238,0.25)] hover:border-[#6FD6C4]/40",
  };

  return (
    <div
      className={`glass-panel rounded-xl p-6 relative overflow-hidden transition-[transform,border-color,box-shadow] duration-200 ${
        hoverEffect ? "glass-panel-hover" : ""
      } ${glowMap[glow]} ${className}`}
      {...props}
    >
      {children}
    </div>
  );
}
