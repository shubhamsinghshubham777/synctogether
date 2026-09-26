import React from "react";
import Link from "next/link";
import { Loader2 } from "lucide-react";

interface PTButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: "primary" | "secondary" | "gold" | "ghost" | "outline";
  size?: "sm" | "md" | "lg";
  href?: string;
  isLoading?: boolean;
  leftIcon?: React.ReactNode;
  rightIcon?: React.ReactNode;
  className?: string;
}

export function PTButton({
  children,
  variant = "primary",
  size = "md",
  href,
  isLoading = false,
  leftIcon,
  rightIcon,
  className = "",
  disabled,
  ...props
}: PTButtonProps) {
  const sizeStyles = {
    sm: "px-3.5 py-1.5 text-xs font-medium rounded-lg gap-1.5",
    md: "px-5 py-2.5 text-sm font-semibold rounded-xl gap-2",
    lg: "px-7 py-3.5 text-base font-bold rounded-xl gap-2.5",
  };

  const variantStyles = {
    // One lit button per view: flat Beam with ink text (btn-primary-gradient
    // carries the colour and the glow). Everything else is an outline.
    primary: "btn-primary-gradient border border-transparent",
    secondary:
      "bg-transparent hover:bg-white/5 text-white border border-rail hover:border-gray-600",
    gold: "btn-gold-gradient border",
    ghost:
      "bg-transparent hover:bg-white/5 text-gray-300 hover:text-white border border-transparent",
    outline:
      "bg-transparent hover:bg-beam-500/10 text-beam-400 hover:text-beam-300 border border-beam-500/40 hover:border-beam-500/70",
  };

  const baseStyles =
    "inline-flex items-center justify-center font-[family-name:var(--font-outfit)] transition-[background-color,border-color,color,box-shadow,transform] duration-150 active:translate-y-px disabled:opacity-50 disabled:pointer-events-none cursor-pointer select-none text-center";

  const content = (
    <>
      {isLoading ? (
        <Loader2 className="w-4 h-4 animate-spin text-current" />
      ) : (
        leftIcon
      )}
      <span>{children}</span>
      {!isLoading && rightIcon}
    </>
  );

  if (href && !disabled && !isLoading) {
    return (
      <Link
        href={href}
        className={`${baseStyles} ${sizeStyles[size]} ${variantStyles[variant]} ${className}`}
      >
        {content}
      </Link>
    );
  }

  return (
    <button
      disabled={disabled || isLoading}
      className={`${baseStyles} ${sizeStyles[size]} ${variantStyles[variant]} ${className}`}
      {...props}
    >
      {content}
    </button>
  );
}
