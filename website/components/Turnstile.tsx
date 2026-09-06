"use client";

import { useEffect, useRef, useImperativeHandle, forwardRef } from "react";
import { isLocalEnvironment } from "@/lib/pricing";

export interface TurnstileHandle {
  execute: () => Promise<string>;
  reset: () => void;
}

interface TurnstileProps {
  onSuccess?: (token: string) => void;
  onError?: (error?: unknown) => void;
  onExpire?: () => void;
  siteKey?: string;
  className?: string;
}

declare global {
  interface Window {
    turnstile?: {
      render: (
        container: string | HTMLElement,
        options: {
          sitekey: string;
          theme?: "light" | "dark" | "auto";
          size?: "normal" | "compact" | "flexible" | "invisible";
          execution?: "render" | "execute";
          callback?: (token: string) => void;
          "error-callback"?: (error?: unknown) => void;
          "expired-callback"?: () => void;
        }
      ) => string;
      execute: (container?: string | HTMLElement | null) => void;
      reset: (widgetId?: string) => void;
      remove: (widgetId?: string) => void;
    };
  }
}

export const Turnstile = forwardRef<TurnstileHandle, TurnstileProps>(
  function Turnstile(
    { onSuccess, onError, onExpire, siteKey, className = "" },
    ref
  ) {
    const containerRef = useRef<HTMLDivElement | null>(null);
    const widgetIdRef = useRef<string | null>(null);
    const pendingExecuteRef = useRef<(() => void) | null>(null);

    const pendingPromiseRef = useRef<{
      resolve: (token: string) => void;
      reject: (err: unknown) => void;
      timeoutId: ReturnType<typeof setTimeout>;
    } | null>(null);

    // Keep callback refs fresh without re-triggering effect
    const onSuccessRef = useRef(onSuccess);
    onSuccessRef.current = onSuccess;
    const onErrorRef = useRef(onError);
    onErrorRef.current = onError;
    const onExpireRef = useRef(onExpire);
    onExpireRef.current = onExpire;

    // Resolve effective site key: custom prop -> env var -> local dev fallback (Cloudflare test key)
    const effectiveSiteKey =
      siteKey ||
      process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY ||
      (isLocalEnvironment() ? "1x00000000000000000000AA" : "");

    useImperativeHandle(ref, () => ({
      execute: () => {
        // If no captcha site key is configured (e.g. self-hoster without captcha), bypass seamlessly
        if (!effectiveSiteKey) {
          return Promise.resolve("");
        }

        return new Promise<string>((resolve, reject) => {
          if (pendingPromiseRef.current) {
            clearTimeout(pendingPromiseRef.current.timeoutId);
            pendingPromiseRef.current.reject(
              new Error("Superseded by new execution")
            );
          }

          const timeoutId = setTimeout(() => {
            if (pendingPromiseRef.current) {
              pendingPromiseRef.current = null;
              reject(
                new Error("Security verification timed out. Please try again.")
              );
            }
          }, 15000);

          pendingPromiseRef.current = { resolve, reject, timeoutId };

          const trigger = () => {
            if (!widgetIdRef.current || !window.turnstile) return;
            try {
              window.turnstile.reset(widgetIdRef.current);
              window.turnstile.execute(widgetIdRef.current);
            } catch (err) {
              clearTimeout(timeoutId);
              pendingPromiseRef.current = null;
              reject(err);
            }
          };

          if (widgetIdRef.current && window.turnstile) {
            trigger();
          } else {
            pendingExecuteRef.current = trigger;
          }
        });
      },
      reset: () => {
        if (widgetIdRef.current && window.turnstile) {
          try {
            window.turnstile.reset(widgetIdRef.current);
          } catch (e) {
            console.error("Failed to reset Turnstile widget:", e);
          }
        }
      },
    }));

    useEffect(() => {
      if (!effectiveSiteKey) {
        onSuccessRef.current?.("");
        return;
      }

      let isMounted = true;

      const renderWidget = () => {
        if (!isMounted || !containerRef.current || !window.turnstile) return;
        if (widgetIdRef.current) return;

        try {
          const id = window.turnstile.render(containerRef.current, {
            sitekey: effectiveSiteKey,
            theme: "dark",
            size: "invisible",
            execution: "execute",
            callback: (token: string) => {
              if (pendingPromiseRef.current) {
                clearTimeout(pendingPromiseRef.current.timeoutId);
                pendingPromiseRef.current.resolve(token);
                pendingPromiseRef.current = null;
              }
              if (isMounted) {
                onSuccessRef.current?.(token);
              }
            },
            "error-callback": (err: unknown) => {
              const errorMsg =
                typeof err === "string" && err.length > 0
                  ? `Security check failed (code: ${err}). Please try again.`
                  : "Security check failed. Please verify and try again.";
              if (pendingPromiseRef.current) {
                clearTimeout(pendingPromiseRef.current.timeoutId);
                pendingPromiseRef.current.reject(new Error(errorMsg));
                pendingPromiseRef.current = null;
              }
              if (isMounted && onErrorRef.current) {
                onErrorRef.current(errorMsg);
              }
            },
            "expired-callback": () => {
              if (pendingPromiseRef.current) {
                clearTimeout(pendingPromiseRef.current.timeoutId);
                pendingPromiseRef.current.reject(
                  new Error("Security check expired. Please try again.")
                );
                pendingPromiseRef.current = null;
              }
              if (isMounted && onExpireRef.current) {
                onExpireRef.current();
              }
            },
          });

          widgetIdRef.current = id;

          // If execution was queued before render completed, run it now
          if (pendingExecuteRef.current) {
            const exec = pendingExecuteRef.current;
            pendingExecuteRef.current = null;
            exec();
          }
        } catch (err) {
          console.error("Turnstile render error:", err);
        }
      };

      const handleScriptError = () => {
        if (pendingPromiseRef.current) {
          clearTimeout(pendingPromiseRef.current.timeoutId);
          pendingPromiseRef.current.reject(
            new Error(
              "Security verification could not be loaded. If you are using an ad blocker, please allow Cloudflare challenges and try again."
            )
          );
          pendingPromiseRef.current = null;
        }
      };

      if (window.turnstile) {
        renderWidget();
      } else {
        const scriptId = "cf-turnstile-script";
        let script = document.getElementById(scriptId) as HTMLScriptElement | null;
        if (!script) {
          script = document.createElement("script");
          script.id = scriptId;
          script.src =
            "https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit";
          script.async = true;
          script.defer = true;
          document.head.appendChild(script);
        }
        script.addEventListener("load", renderWidget);
        script.addEventListener("error", handleScriptError);

        return () => {
          isMounted = false;
          script?.removeEventListener("load", renderWidget);
          script?.removeEventListener("error", handleScriptError);
          if (widgetIdRef.current && window.turnstile) {
            try {
              window.turnstile.remove(widgetIdRef.current);
            } catch {
              // ignore cleanup error
            }
            widgetIdRef.current = null;
          }
        };
      }

      return () => {
        isMounted = false;
        if (widgetIdRef.current && window.turnstile) {
          try {
            window.turnstile.remove(widgetIdRef.current);
          } catch {
            // ignore cleanup error
          }
          widgetIdRef.current = null;
        }
      };
    }, [effectiveSiteKey]);

    if (!effectiveSiteKey) {
      return null;
    }

    // With size: "invisible", Cloudflare manages the widget's hidden state and injects an overlay modal
    // only if an interactive challenge is triggered. The container must allow the modal to be visible.
    return (
      <div
        ref={containerRef}
        className={`fixed top-0 left-0 w-0 h-0 overflow-visible pointer-events-auto z-[99999] ${className}`}
        aria-hidden="true"
      />
    );
  }
);
