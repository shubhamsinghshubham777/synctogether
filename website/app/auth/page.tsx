"use client";

import { Suspense, useEffect, useRef, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { Logo } from "@/components/Logo";
import { AppleLogo } from "@/components/Icons";
import { GlassPanel } from "@/components/GlassPanel";
import { createClient } from "@/lib/supabase/client";
import { Turnstile, type TurnstileHandle } from "@/components/Turnstile";
import { ShieldCheck, Info, Loader2, Mail, ArrowLeft, Check, RefreshCw, AlertCircle } from "lucide-react";

function AuthCard() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const redirect = searchParams.get("redirect") || "/account";
  const [checkingAuth, setCheckingAuth] = useState(true);
  const [oauthLoading, setOauthLoading] = useState<"google" | "apple" | null>(null);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [infoMsg, setInfoMsg] = useState<string | null>(null);

  // Email OTP state
  const [email, setEmail] = useState("");
  const [otpToken, setOtpToken] = useState("");
  const [isOtpSent, setIsOtpSent] = useState(false);
  const [emailLoading, setEmailLoading] = useState(false);
  const [otpLoading, setOtpLoading] = useState(false);
  const [resendCooldown, setResendCooldown] = useState(0);
  const turnstileRef = useRef<TurnstileHandle | null>(null);

  const supabase = createClient();

  useEffect(() => {
    let ignore = false;

    async function checkExistingSession() {
      try {
        const {
          data: { user },
        } = await supabase.auth.getUser();
        if (ignore) return;
        if (user) {
          router.replace(redirect);
          return;
        }
      } catch (err) {
        console.error("Auth check failed:", err);
      } finally {
        if (!ignore) {
          setCheckingAuth(false);
        }
      }
    }

    checkExistingSession();

    const { data: authListener } = supabase.auth.onAuthStateChange(
      (_event, session) => {
        if (session?.user) {
          router.replace(redirect);
        }
      }
    );

    return () => {
      ignore = true;
      authListener.subscription.unsubscribe();
    };
  }, [redirect, router, supabase]);

  useEffect(() => {
    if (resendCooldown <= 0) return;
    const timer = setInterval(() => {
      setResendCooldown((prev) => (prev <= 1 ? 0 : prev - 1));
    }, 1000);
    return () => clearInterval(timer);
  }, [resendCooldown]);

  useEffect(() => {
    const parseUrlErrors = () => {
      let message: string | null = null;

      // 1. Check URL hash fragment (Supabase auth errors e.g. expired link redirect with hash fragment)
      if (typeof window !== "undefined" && window.location.hash) {
        try {
          const rawHash = window.location.hash.startsWith("#")
            ? window.location.hash.slice(1)
            : window.location.hash;
          const hashParams = new URLSearchParams(rawHash);
          const desc = hashParams.get("error_description");
          const code = hashParams.get("error_code");
          const err = hashParams.get("error");

          if (desc) {
            message = desc.replace(/\+/g, " ");
          } else if (code === "otp_expired") {
            message = "Email link is invalid or has expired. Please request a new code.";
          } else if (err) {
            message = err.replace(/\+/g, " ");
          }
        } catch (e) {
          console.error("Failed to parse URL hash parameters:", e);
        }
      }

      // 2. Fall back to search parameters (?error_description=... or ?error=...)
      if (!message) {
        const desc = searchParams.get("error_description");
        const err = searchParams.get("error");
        if (desc) {
          message = desc.replace(/\+/g, " ");
        } else if (err) {
          message = err.replace(/\+/g, " ");
        }
      }

      if (message) {
        setErrorMsg(message);
      }
    };

    parseUrlErrors();

    window.addEventListener("hashchange", parseUrlErrors);
    return () => window.removeEventListener("hashchange", parseUrlErrors);
  }, [searchParams]);

  const handleGoogleSignIn = async () => {
    setOauthLoading("google");
    setErrorMsg(null);
    try {
      const redirectTo = `${window.location.origin}/auth/callback?redirect=${encodeURIComponent(
        redirect
      )}`;

      const { error } = await supabase.auth.signInWithOAuth({
        provider: "google",
        options: {
          redirectTo,
          queryParams: {
            access_type: "offline",
            prompt: "consent",
          },
        },
      });

      if (error) throw error;
    } catch (err: unknown) {
      console.error("Google sign in error:", err);
      setErrorMsg(
        err instanceof Error ? err.message : "Failed to initiate Google sign in"
      );
      setOauthLoading(null);
    }
  };

  const handleAppleSignIn = async () => {
    setOauthLoading("apple");
    setErrorMsg(null);
    try {
      const redirectTo = `${window.location.origin}/auth/callback?redirect=${encodeURIComponent(
        redirect
      )}`;

      const { error } = await supabase.auth.signInWithOAuth({
        provider: "apple",
        options: {
          redirectTo,
        },
      });

      if (error) throw error;
    } catch (err: unknown) {
      console.error("Apple sign in error:", err);
      setErrorMsg(
        err instanceof Error ? err.message : "Failed to initiate Apple sign in"
      );
      setOauthLoading(null);
    }
  };

  const handleSendEmailOtp = async (e?: React.FormEvent) => {
    if (e) e.preventDefault();
    const cleanEmail = email.trim();
    if (!cleanEmail || !cleanEmail.includes("@") || !cleanEmail.includes(".")) {
      setErrorMsg("Please enter a valid email address.");
      return;
    }
    setEmailLoading(true);
    setErrorMsg(null);
    setInfoMsg(null);
    try {
      // Execute bot protection check on demand upon clicking "Send code"
      const captchaToken = await turnstileRef.current?.execute();

      const redirectTo = `${window.location.origin}/auth/callback?redirect=${encodeURIComponent(
        redirect
      )}`;
      const { error } = await supabase.auth.signInWithOtp({
        email: cleanEmail,
        options: {
          emailRedirectTo: redirectTo,
          captchaToken: captchaToken || undefined,
        },
      });
      if (error) throw error;
      setIsOtpSent(true);
      setResendCooldown(30);
      setInfoMsg(`Verification code sent to ${cleanEmail}`);
    } catch (err: unknown) {
      console.error("Email OTP send error:", err);
      setErrorMsg(
        err instanceof Error ? err.message : "Failed to send verification code"
      );
      turnstileRef.current?.reset();
    } finally {
      setEmailLoading(false);
    }
  };

  const handleVerifyOtp = async (e?: React.FormEvent) => {
    if (e) e.preventDefault();
    const cleanToken = otpToken.trim();
    if (cleanToken.length !== 6) {
      setErrorMsg("Please enter the 6-digit code.");
      return;
    }
    setOtpLoading(true);
    setErrorMsg(null);
    try {
      const { error } = await supabase.auth.verifyOtp({
        email: email.trim(),
        token: cleanToken,
        type: "email",
      });
      if (error) throw error;
      router.replace(redirect);
    } catch (err: unknown) {
      console.error("OTP verify error:", err);
      setErrorMsg(
        err instanceof Error ? err.message : "Invalid or expired verification code"
      );
      setOtpLoading(false);
    }
  };

  const isAnyLoading = oauthLoading !== null || emailLoading || otpLoading;

  if (checkingAuth) {
    return (
      <GlassPanel
        glow="purple"
        className="p-8 sm:p-10 space-y-4 max-w-md w-full border-purple-500/25 bg-[#141024]/90 text-center"
      >
        <div className="flex justify-center mb-2">
          <Logo size="lg" showText={false} />
        </div>
        <div className="flex items-center justify-center gap-2 text-sm text-purple-200 py-4">
          <Loader2 className="w-4 h-4 animate-spin text-purple-400" />
          <span>Verifying session...</span>
        </div>
      </GlassPanel>
    );
  }

  return (
    <>
      {/* Invisible Bot Protection (Triggered on demand upon submitting) */}
      <Turnstile ref={turnstileRef} />

      <GlassPanel
        glow="purple"
        className="p-8 sm:p-10 space-y-5 max-w-md w-full border-purple-500/25 bg-[#141024]/90"
      >
        <div className="text-center space-y-3">
          <div className="flex justify-center mb-2">
            <Logo size="lg" showText={false} />
          </div>
          <h1 className="text-2xl font-bold text-white font-[family-name:var(--font-space-grotesk)]">
            Welcome to SyncTogether
          </h1>
          <p className="text-xs text-gray-400 leading-relaxed">
            Sign in to manage your subscription, host watch parties, and sync across all your devices.
          </p>
        </div>

        {errorMsg && (
          <div className="p-3.5 rounded-xl bg-rose-500/10 border border-rose-500/25 text-rose-300 text-xs flex items-start gap-2.5 leading-relaxed">
            <AlertCircle className="w-4 h-4 text-rose-400 shrink-0 mt-0.5" />
            <span className="flex-1">{errorMsg}</span>
          </div>
        )}

        {infoMsg && (
          <div className="p-3 rounded-xl bg-purple-500/10 border border-purple-400/20 text-purple-200 text-xs flex items-center gap-2">
            <Check className="w-4 h-4 text-emerald-400 shrink-0" />
            <span>{infoMsg}</span>
          </div>
        )}

        {/* OAuth Buttons */}
        {!isOtpSent && (
          <div className="space-y-3">
            {/* Apple Sign-in Button */}
            <button
              onClick={handleAppleSignIn}
              disabled={isAnyLoading}
              className="w-full py-3 px-4 rounded-xl bg-black hover:bg-zinc-900 text-white font-semibold text-sm flex items-center justify-center gap-3 transition-all duration-200 border border-white/15 shadow-lg shadow-black/40 active:scale-[0.98] cursor-pointer disabled:opacity-50"
            >
              <AppleLogo className="w-4 h-4" />
              <span>
                {oauthLoading === "apple" ? "Connecting to Apple..." : "Continue with Apple"}
              </span>
            </button>

            {/* Google Sign-in Button */}
            <button
              onClick={handleGoogleSignIn}
              disabled={isAnyLoading}
              className="w-full py-3 px-4 rounded-xl bg-white hover:bg-gray-100 text-gray-900 font-semibold text-sm flex items-center justify-center gap-3 transition-all duration-200 shadow-lg shadow-white/5 active:scale-[0.98] cursor-pointer disabled:opacity-50"
            >
              <svg className="w-5 h-5" viewBox="0 0 24 24">
                <path
                  fill="#4285F4"
                  d="M23.745 12.27c0-.7-.06-1.4-.19-2.07H12v4.51h6.6c-.29 1.52-1.14 2.82-2.4 3.68v3.05h3.88c2.27-2.09 3.665-5.17 3.665-9.17z"
                />
                <path
                  fill="#34A853"
                  d="M12 24c3.24 0 5.95-1.08 7.93-2.91l-3.88-3.05c-1.08.72-2.45 1.16-4.05 1.16-3.12 0-5.77-2.1-6.72-4.93H1.25v3.15C3.26 21.36 7.33 24 12 24z"
                />
                <path
                  fill="#FBBC05"
                  d="M5.28 14.27c-.25-.72-.38-1.49-.38-2.27s.13-1.55.38-2.27V6.58H1.25C.45 8.18 0 10.02 0 12s.45 3.82 1.25 5.42l4.03-3.15z"
                />
                <path
                  fill="#EA4335"
                  d="M12 4.75c1.77 0 3.35.61 4.6 1.8l3.42-3.42C17.95 1.19 15.24 0 12 0 7.33 0 3.26 2.64 1.25 6.58l4.03 3.15c.95-2.83 3.6-4.98 6.72-4.98z"
                />
              </svg>
              <span>
                {oauthLoading === "google" ? "Connecting to Google..." : "Continue with Google"}
              </span>
            </button>
          </div>
        )}

        {/* Divider */}
        <div className="relative flex items-center justify-center pt-1 pb-2">
          <div className="border-t border-white/10 w-full" />
          <span className="bg-[#141024] px-3 text-[11px] font-medium text-gray-400 shrink-0 uppercase tracking-wider">
            {isOtpSent ? "Verification code" : "or continue with email"}
          </span>
          <div className="border-t border-white/10 w-full" />
        </div>

        {/* Email Form / OTP Form */}
        {!isOtpSent ? (
          <form onSubmit={handleSendEmailOtp} className="space-y-3">
            <div className="relative">
              <Mail className="w-4 h-4 text-gray-400 absolute left-3.5 top-1/2 -translate-y-1/2 pointer-events-none" />
              <input
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="name@example.com"
                disabled={isAnyLoading}
                required
                className="w-full pl-10 pr-4 py-2.5 rounded-xl bg-white/[0.04] border border-white/10 text-white text-sm placeholder:text-gray-500 focus:outline-none focus:border-purple-400/80 transition-colors"
              />
            </div>

            <button
              type="submit"
              disabled={isAnyLoading || !email}
              className="w-full py-2.5 px-4 rounded-xl bg-purple-600 hover:bg-purple-500 text-white font-semibold text-sm flex items-center justify-center gap-2 transition-all duration-200 active:scale-[0.98] cursor-pointer disabled:cursor-not-allowed disabled:opacity-50 disabled:active:scale-100"
            >
              {emailLoading ? (
                <>
                  <Loader2 className="w-4 h-4 animate-spin" />
                  <span>Sending code...</span>
                </>
              ) : (
                <span>Send code</span>
              )}
            </button>
          </form>
        ) : (
          <form onSubmit={handleVerifyOtp} className="space-y-3.5">
            <div className="space-y-1.5">
              <p className="text-xs text-gray-300">
                Enter the 6-digit code sent to <strong className="text-white">{email}</strong>
              </p>
              <input
                type="text"
                inputMode="numeric"
                pattern="[0-9]*"
                maxLength={6}
                value={otpToken}
                onChange={(e) => {
                  const val = e.target.value.replace(/\D/g, "").slice(0, 6);
                  setOtpToken(val);
                  if (val.length === 6) {
                    supabase.auth
                      .verifyOtp({
                        email: email.trim(),
                        token: val,
                        type: "email",
                      })
                      .then(({ error }) => {
                        if (!error) {
                          router.replace(redirect);
                        } else {
                          setErrorMsg(error.message);
                        }
                      });
                  }
                }}
                placeholder="000000"
                disabled={isAnyLoading}
                autoFocus
                className="w-full text-center tracking-[0.5em] font-mono text-xl py-2.5 rounded-xl bg-white/[0.06] border border-purple-400/30 text-white placeholder:text-gray-600 focus:outline-none focus:border-purple-400 transition-colors"
              />
            </div>

            <button
              type="submit"
              disabled={isAnyLoading || otpToken.length !== 6}
              className="w-full py-2.5 px-4 rounded-xl bg-purple-600 hover:bg-purple-500 text-white font-semibold text-sm flex items-center justify-center gap-2 transition-all duration-200 active:scale-[0.98] cursor-pointer disabled:cursor-not-allowed disabled:opacity-50 disabled:active:scale-100"
            >
              {otpLoading ? (
                <>
                  <Loader2 className="w-4 h-4 animate-spin" />
                  <span>Verifying...</span>
                </>
              ) : (
                <span>Verify & Sign in</span>
              )}
            </button>

            <div className="flex items-center justify-between text-xs text-gray-400 pt-1">
              <button
                type="button"
                onClick={() => {
                  setIsOtpSent(false);
                  setOtpToken("");
                  setErrorMsg(null);
                  setInfoMsg(null);
                }}
                className="inline-flex items-center gap-1 text-purple-300/80 hover:text-purple-200 cursor-pointer"
              >
                <ArrowLeft className="w-3.5 h-3.5" />
                <span>Change email</span>
              </button>

              <button
                type="button"
                disabled={resendCooldown > 0 || emailLoading}
                onClick={() => handleSendEmailOtp()}
                className="inline-flex items-center gap-1 text-purple-300/80 hover:text-purple-200 cursor-pointer disabled:text-gray-600 disabled:cursor-not-allowed"
              >
                <RefreshCw className="w-3 h-3" />
                <span>
                  {resendCooldown > 0 ? `Resend (${resendCooldown}s)` : "Resend code"}
                </span>
              </button>
            </div>
          </form>
        )}

        {/* Info Notice */}
        <div className="p-3.5 rounded-xl bg-purple-500/10 border border-purple-400/20 text-[11px] text-purple-200/90 leading-relaxed flex items-start gap-2.5">
          <Info className="w-4 h-4 text-purple-300 shrink-0 mt-0.5" />
          <span>
            Signing in syncs your subscription, watch parties, and account settings seamlessly between the web and desktop app.
          </span>
        </div>

        <div className="pt-2 border-t border-white/5 text-center">
          <p className="text-[11px] text-gray-500 flex items-center justify-center gap-1.5">
            <ShieldCheck className="w-3.5 h-3.5 text-emerald-400" />
            <span>Encrypted authentication</span>
          </p>
        </div>
      </GlassPanel>
    </>
  );
}

export default function AuthPage() {
  return (
    <div className="min-h-[80vh] flex items-center justify-center px-4 py-12 relative overflow-hidden">
      {/* Background Ambient Glow */}
      <div className="glow-blob-purple top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 opacity-30" />

      <Suspense
        fallback={
          <GlassPanel className="p-8 max-w-md w-full text-center text-sm text-gray-400">
            Loading authentication...
          </GlassPanel>
        }
      >
        <AuthCard />
      </Suspense>
    </div>
  );
}
