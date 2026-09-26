"use client";

import { Suspense, useEffect, useRef, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { AppleLogo } from "@/components/Icons";
import { Ticket } from "@/components/Ticket";
import { Kicker, Headline, display, mono } from "@/components/booth/Booth";
import { createClient } from "@/lib/supabase/client";
import { Turnstile, type TurnstileHandle } from "@/components/Turnstile";
import { Loader2, Mail, ArrowLeft, Check, RefreshCw, AlertCircle } from "lucide-react";

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

  const inputBase =
    "w-full rounded-[4px] bg-booth border border-rail text-white placeholder:text-gray-600 focus:outline-none focus:border-beam-500 transition-colors disabled:opacity-60";
  const primaryBtn =
    "w-full py-3 px-4 rounded-[4px] font-semibold text-[15px] flex items-center justify-center gap-2 transition-colors";
  const btnState = (enabled: boolean) =>
    enabled
      ? "btn-primary-gradient active:translate-y-px cursor-pointer"
      : "bg-transparent border border-rail text-gray-500 cursor-not-allowed";
  const emailValid = /\S+@\S+\.\S+/.test(email.trim());

  if (checkingAuth) {
    return (
      <div className="w-full max-w-[460px] bg-seat ring-1 ring-inset ring-rail rounded-md p-8 sm:p-10 flex flex-col items-center gap-5 text-center">
        <span className="sync-dot" aria-hidden="true" />
        <p className={`${mono} text-xs tracking-[0.16em] uppercase text-gray-500`}>Checking your ticket…</p>
      </div>
    );
  }

  return (
    <>
      {/* Invisible Bot Protection (Triggered on demand upon submitting) */}
      <Turnstile ref={turnstileRef} />

      <div className="w-full max-w-[460px] bg-seat ring-1 ring-inset ring-rail rounded-md p-6 sm:p-9 space-y-6">
        <div className="flex items-baseline justify-between gap-4">
          <Kicker tone="muted">{isOtpSent ? "Box office · step 2 of 2" : "Box office"}</Kicker>
          <span className={`${mono} text-[11px] text-gray-600`}>{isOtpSent ? "CODE" : "SIGN IN"}</span>
        </div>

        {errorMsg && (
          <div role="alert" className="border-l-2 border-signal pl-4 py-1 text-sm text-gray-200 flex items-start gap-2.5 leading-relaxed">
            <AlertCircle className="w-4 h-4 text-signal shrink-0 mt-0.5" />
            <span className="flex-1 min-w-0 break-words">{errorMsg}</span>
          </div>
        )}

        {infoMsg && (
          <div role="status" className="border-l-2 border-cue pl-4 py-1 text-sm text-gray-200 flex items-start gap-2.5">
            <Check className="w-4 h-4 text-cue shrink-0 mt-0.5" />
            <span className="min-w-0 break-words">{infoMsg}</span>
          </div>
        )}

        {/* OAuth Buttons */}
        {!isOtpSent && (
          <div className="space-y-3">
            {/* Apple Sign-in Button */}
            <button
              onClick={handleAppleSignIn}
              disabled={isAnyLoading}
              className="w-full py-3 px-4 rounded-[4px] bg-transparent hover:bg-booth text-white font-semibold text-[15px] flex items-center justify-center gap-3 transition-colors border border-rail hover:border-gray-500 active:translate-y-px cursor-pointer disabled:opacity-50"
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
              className="w-full py-3 px-4 rounded-[4px] bg-transparent hover:bg-booth text-white border border-rail hover:border-gray-500 font-semibold text-[15px] flex items-center justify-center gap-3 transition-colors active:translate-y-px cursor-pointer disabled:opacity-50"
            >
              <svg className="w-5 h-5" viewBox="0 0 24 24" aria-hidden="true">
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

        {/* Divider: a perforation */}
        <div className="flex items-center gap-3" aria-hidden={isOtpSent ? undefined : true}>
          <div className="flex-1 border-t-2 border-dashed border-rail" />
          <span className={`${mono} text-[10px] tracking-[0.16em] uppercase text-gray-500 shrink-0`}>
            {isOtpSent ? "Verification code" : "or by email"}
          </span>
          <div className="flex-1 border-t-2 border-dashed border-rail" />
        </div>

        {/* Email Form / OTP Form */}
        {!isOtpSent ? (
          <form onSubmit={handleSendEmailOtp} className="space-y-3">
            <label className="block">
              <span className={`${mono} block mb-2.5 text-[11px] tracking-[0.16em] uppercase text-gray-500`}>Email</span>
              <span className="relative block">
                <Mail className="w-4 h-4 text-gray-500 absolute left-3.5 top-1/2 -translate-y-1/2 pointer-events-none" />
                <input
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="name@example.com"
                  disabled={isAnyLoading}
                  required
                  className={`${inputBase} pl-10 pr-4 py-3 text-[15px]`}
                />
              </span>
            </label>

            <button type="submit" disabled={isAnyLoading || !email} className={`${primaryBtn} ${btnState(emailValid || emailLoading)}`}>
              {emailLoading ? (
                <>
                  <Loader2 className="w-4 h-4 animate-spin" />
                  <span>Sending code...</span>
                </>
              ) : (
                <span>Send me a code</span>
              )}
            </button>
          </form>
        ) : (
          <form onSubmit={handleVerifyOtp} className="space-y-4">
            <div className="space-y-2">
              <p className="text-sm text-gray-400">
                Six digits, sent to <strong className="text-white font-semibold break-all">{email}</strong>
              </p>
              <input
                type="text"
                inputMode="numeric"
                pattern="[0-9]*"
                maxLength={6}
                aria-label="6-digit code"
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
                className={`${inputBase} ${mono} text-center tracking-[0.5em] text-2xl py-3.5`}
              />
            </div>

            <button type="submit" disabled={isAnyLoading || otpToken.length !== 6} className={`${primaryBtn} ${btnState(otpToken.length === 6 || otpLoading)}`}>
              {otpLoading ? (
                <>
                  <Loader2 className="w-4 h-4 animate-spin" />
                  <span>Verifying...</span>
                </>
              ) : (
                <span>Verify &amp; take your seat</span>
              )}
            </button>

            <div className="flex items-center justify-between gap-3 text-sm pt-1">
              <button
                type="button"
                onClick={() => {
                  setIsOtpSent(false);
                  setOtpToken("");
                  setErrorMsg(null);
                  setInfoMsg(null);
                }}
                className="inline-flex items-center gap-1.5 text-gray-400 hover:text-white cursor-pointer transition-colors"
              >
                <ArrowLeft className="w-3.5 h-3.5" />
                <span>Change email</span>
              </button>

              <button
                type="button"
                disabled={resendCooldown > 0 || emailLoading}
                onClick={() => handleSendEmailOtp()}
                className={`${mono} inline-flex items-center gap-1.5 text-xs text-gray-400 hover:text-white cursor-pointer disabled:text-gray-600 disabled:cursor-not-allowed transition-colors`}
              >
                <RefreshCw className="w-3 h-3" />
                <span>
                  {resendCooldown > 0 ? `Resend (${resendCooldown}s)` : "Resend code"}
                </span>
              </button>
            </div>
          </form>
        )}

        {!isOtpSent && (
          <p className="-mt-2 text-[13px] text-gray-500 leading-relaxed">
            A 6-digit code, every time. Set a password in the app&apos;s profile if you want
            one. The code still always works.
          </p>
        )}
      </div>
    </>
  );
}

export default function AuthPage() {
  return (
    <div className="px-4 sm:px-6 lg:px-8 max-w-6xl mx-auto py-10 md:py-12 grid lg:grid-cols-[minmax(0,1fr)_460px] gap-12 lg:gap-24 items-start lg:items-center lg:min-h-[704px] lg:py-10">
      <div className="space-y-[26px]">
        <div className="space-y-[26px]">
          <Kicker>Members&apos; entrance</Kicker>
          <Headline className="text-[clamp(2.75rem,7vw,6rem)] leading-[0.88] tracking-[-0.045em]">
            <span className="line-in">Take your</span>
            <span className="line-in [animation-delay:90ms] text-beam-500">seat.</span>
          </Headline>
          <p className="text-lg text-gray-400 leading-[1.55] max-w-[460px]">
            Sign in to manage your Patron seat and keep your streak. Joining
            somebody&apos;s room never needs an account.
          </p>
        </div>
        <div className="hidden sm:block max-w-[440px]">
          <Ticket
            animate
            className="min-h-[130px]"
            stubClassName="w-[120px]"
            stub={
              <span className={`${mono} text-sm sm:text-base font-semibold tracking-[0.08em] text-booth`}>ADMIT&nbsp;1</span>
            }
          >
            <p className={`${mono} text-[11px] tracking-[0.14em] text-booth/60`}>SYNCTOGETHER · MEMBERS</p>
            <p className={`${display} mt-1.5 text-2xl font-extrabold tracking-[-0.035em] leading-[0.98]`}>
              One account, web and app.
            </p>
            <p className="mt-2 text-sm text-booth/70">Mac · Windows · this website</p>
          </Ticket>
        </div>
      </div>

      <div className="flex justify-center lg:justify-end">
        <Suspense
          fallback={
            <div className="w-full max-w-[460px] bg-seat ring-1 ring-inset ring-rail rounded-md p-8 text-center">
              <p className={`${mono} text-xs tracking-[0.16em] uppercase text-gray-500`}>Opening the box office…</p>
            </div>
          }
        >
          <AuthCard />
        </Suspense>
      </div>
    </div>
  );
}
