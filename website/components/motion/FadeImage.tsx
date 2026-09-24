"use client";

import Image, { type ImageProps } from "next/image";
import { useState } from "react";

/**
 * next/image that stays invisible until its bytes have decoded, then fades in -
 * so a shot arrives whole instead of painting top-down. Reserve the box with
 * width/height (or fill) as usual; that is what stops the layout shifting.
 */
export function FadeImage({ className = "", onLoad, alt, ...props }: ImageProps) {
  const [loaded, setLoaded] = useState(false);
  return (
    <Image
      {...props}
      alt={alt}
      onLoad={(e) => {
        setLoaded(true);
        onLoad?.(e);
      }}
      className={`${className} transition-opacity duration-700 ease-out motion-reduce:transition-none ${
        loaded ? "opacity-100" : "opacity-0"
      }`}
    />
  );
}
