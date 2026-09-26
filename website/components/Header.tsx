"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { Logo } from "./Logo";
import { PTButton } from "./PTButton";
import { createClient } from "@/lib/supabase/client";
import { Menu, X, User as UserIcon, Sparkles } from "lucide-react";
import type { User } from "@supabase/supabase-js";
import Image from "next/image";

/** The boards' header button: 40px, 22px sides, 14px semibold on a #5A4F44 edge. */
const HEADER_BTN = "!h-10 !px-[22px] !rounded-[4px] !text-sm !font-semibold !border-[#5A4F44]";

export function Header() {
  const [user, setUser] = useState<User | null>(null);
  const [isPremium, setIsPremium] = useState(false);
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);
  // Clear at the top so the hero's glow and stamp read uncut, as on the boards.
  const [scrolled, setScrolled] = useState(false);
  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 0);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);
  const pathname = usePathname();
  const supabase = createClient();

  useEffect(() => {
    let ignore = false;
    let channel: ReturnType<typeof supabase.channel> | null = null;

    async function checkTier(userId?: string) {
      if (!userId) {
        if (!ignore) setIsPremium(false);
        return;
      }
      try {
        const { data: entData } = await supabase.rpc("my_entitlement");
        if (ignore) return;
        if (entData) {
          const ent = Array.isArray(entData) ? entData[0] : entData;
          setIsPremium(ent?.tier === "premium");
        } else {
          const { data: sub } = await supabase
            .from("subscriptions")
            .select("tier, current_period_end")
            .eq("user_id", userId)
            .maybeSingle();
          if (ignore) return;
          if (sub?.tier === "premium") {
            const isExpired =
              sub.current_period_end && new Date(sub.current_period_end) < new Date();
            setIsPremium(!isExpired);
          } else {
            setIsPremium(false);
          }
        }
      } catch {
        if (!ignore) setIsPremium(false);
      }
    }

    async function getUser() {
      const {
        data: { user },
      } = await supabase.auth.getUser();
      if (ignore) return;
      setUser(user);
      if (user) {
        checkTier(user.id);
        const channelName = `header_subs_${user.id}_${Date.now()}`;
        channel = supabase
          .channel(channelName)
          .on(
            "postgres_changes",
            {
              event: "*",
              schema: "public",
              table: "subscriptions",
              filter: `user_id=eq.${user.id}`,
            },
            () => {
              checkTier(user.id);
            }
          )
          .subscribe();
      }
    }
    getUser();

    const { data: authListener } = supabase.auth.onAuthStateChange(
      (_event, session) => {
        const currentUser = session?.user ?? null;
        setUser(currentUser);
        if (currentUser) {
          checkTier(currentUser.id);
        } else {
          setIsPremium(false);
        }
      }
    );

    return () => {
      ignore = true;
      authListener.subscription.unsubscribe();
      if (channel) {
        supabase.removeChannel(channel);
      }
    };
  }, [supabase]);


  const navLinks = [
    { name: "How it works", href: "/#how" },
    { name: "Pricing", href: "/pricing" },
    { name: "FAQ", href: "/faq" },
    { name: "Changelog", href: "/changelog" },
  ];

  return (
    <header
      className={`fixed top-0 inset-x-0 z-50 h-[60px] md:h-[76px] flex items-center border-b transition-[background-color,border-color] duration-300 ${
        scrolled ? "bg-booth border-aisle" : "bg-transparent border-aisle/60"
      }`}
    >
      <div className="w-full max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 flex items-center justify-between">
        {/* Brand Logo */}
        <Logo />

        {/* Desktop Nav Links */}
        <nav className="hidden md:flex items-center gap-8">
          {navLinks.map((link) => {
            // "How it works" lives on the home page, so it lights for all of "/".
            const isActive = pathname === link.href || (pathname === "/" && link.href.startsWith("/#"));
            return (
              <Link
                key={link.name}
                href={link.href}
                className={`nav-link relative text-[15px] font-medium transition-colors duration-200 ${
                  isActive ? "text-white nav-link-active" : "text-gray-300 hover:text-white"
                }`}
              >
                {link.name}
              </Link>
            );
          })}
        </nav>

        {/* Desktop Actions / Auth State */}
        <div className="hidden md:flex items-center gap-4">
          {user ? (
            <div className="flex items-center gap-[22px]">
              <Link href="/account" className="flex items-center gap-2.5 text-sm font-medium text-white hover:text-beam-400 transition-colors">
                {user.user_metadata?.avatar_url ? (
                  <Image
                    src={user.user_metadata.avatar_url}
                    alt=""
                    width={28}
                    height={28}
                    className={`w-7 h-7 rounded-full ${isPremium ? "shadow-[0_0_0_2px_var(--color-booth),0_0_0_4px_var(--color-brass)]" : "shadow-[0_0_0_2px_var(--color-booth),0_0_0_4px_var(--color-rail)]"}`}
                  />
                ) : (
                  <span
                    className={`w-7 h-7 rounded-full flex items-center justify-center text-[11px] font-semibold text-screen bg-[#7A5CFF] ${
                      isPremium
                        ? "shadow-[0_0_0_2px_var(--color-booth),0_0_0_4px_var(--color-brass)]"
                        : "shadow-[0_0_0_2px_var(--color-booth),0_0_0_4px_var(--color-rail)]"
                    }`}
                  >
                    {(user.user_metadata?.full_name || user.email || "U").charAt(0).toUpperCase()}
                  </span>
                )}
                <span className="max-w-[120px] truncate">
                  {(user.user_metadata?.full_name || user.email?.split("@")[0] || "").split(" ")[0]}
                </span>
              </Link>
              <PTButton href="/download" variant="secondary" className={HEADER_BTN}>
                Download
              </PTButton>
            </div>
          ) : (
            <div className="flex items-center gap-[22px]">
              <Link href="/auth" className="text-sm font-medium text-gray-300 hover:text-white transition-colors">
                Sign in
              </Link>
              {/* Outlined on purpose: the hero owns the page's one lit button. */}
              <PTButton href="/download" variant="secondary" className={HEADER_BTN}>
                Download
              </PTButton>
            </div>
          )}
        </div>

        {/* Phone: logo + Download + menu. Outlined: the hero owns the lit button. */}
        <div className="md:hidden flex items-center gap-1">
        <PTButton href="/download" variant="secondary" className="!h-9 !px-[22px] !rounded-[4px] !text-[13px] !font-semibold !border-[#5A4F44]">
          Download
        </PTButton>
        <button
          onClick={() => setMobileMenuOpen(!mobileMenuOpen)}
          className="md:hidden w-11 h-11 flex items-center justify-center text-white hover:bg-white/5 rounded-[4px] transition-colors duration-200"
          aria-label="Toggle Navigation Menu"
          aria-expanded={mobileMenuOpen}
          aria-controls="mobile-nav"
        >
          {/* Both glyphs stay mounted so the swap can cross-fade */}
          <span className="relative block w-[22px] h-[22px]">
            <Menu
              strokeWidth={1.8}
              className={`absolute inset-0 w-[22px] h-[22px] transition-all duration-300 ease-out ${
                mobileMenuOpen
                  ? "opacity-0 rotate-90 scale-75"
                  : "opacity-100 rotate-0 scale-100"
              }`}
            />
            <X
              strokeWidth={1.8}
              className={`absolute inset-0 w-[22px] h-[22px] transition-all duration-300 ease-out ${
                mobileMenuOpen
                  ? "opacity-100 rotate-0 scale-100"
                  : "opacity-0 -rotate-90 scale-75"
              }`}
            />
          </span>
        </button>
        </div>
      </div>

      {/* Mobile Navigation Drawer - always mounted so it can animate both ways.
          Height rides on grid-template-rows (0fr -> 1fr) rather than max-height,
          so the travel matches the real content height whatever the auth state.
          Nothing above the blurred panel animates opacity: an ancestor with
          opacity < 1 becomes a backdrop root and the backdrop-filter would blur
          an empty layer mid-transition. `inert` keeps the collapsed links out
          of the tab order: they stay mounted for the animation, and
          pointer-events alone would not stop a keyboard tabbing into a
          zero-height panel. */}
      <div
        id="mobile-nav"
        aria-hidden={!mobileMenuOpen}
        inert={!mobileMenuOpen}
        className={`md:hidden absolute top-full inset-x-0 grid overflow-hidden transition-[grid-template-rows] duration-300 ease-[cubic-bezier(0.22,1,0.36,1)] ${
          mobileMenuOpen
            ? "grid-rows-[1fr]"
            : "grid-rows-[0fr] pointer-events-none"
        }`}
      >
        <div className="min-h-0">
          <div
            className={`bg-booth border-b border-aisle px-4 py-6 space-y-4 shadow-2xl transition-all duration-300 ease-out ${
              mobileMenuOpen
                ? "opacity-100 translate-y-0 delay-75"
                : "opacity-0 -translate-y-2"
            }`}
          >
            <nav className="flex flex-col space-y-3">
              {navLinks.map((link) => (
                <Link
                  key={link.name}
                  href={link.href}
                  onClick={() => setMobileMenuOpen(false)}
                  className="text-base font-medium text-gray-200 hover:text-beam-500 py-2 border-b border-aisle"
                >
                  {link.name}
                </Link>
              ))}
            </nav>

            <div className="pt-4 border-t border-aisle flex flex-col gap-3">
              {user ? (
                <>
                  <Link
                    href="/account"
                    onClick={() => setMobileMenuOpen(false)}
                    className={`flex items-center justify-between p-3 rounded-md bg-seat border ${
                      isPremium ? "border-brass" : "border-rail"
                    }`}
                  >
                    <div className="flex items-center gap-3">
                      {user.user_metadata?.avatar_url ? (
                        <Image
                          src={user.user_metadata.avatar_url}
                          alt={user.user_metadata?.full_name || "Profile"}
                          width={32}
                          height={32}
                          className={`w-8 h-8 rounded-full border ${
                            isPremium ? "border-brass" : "border-rail"
                          }`}
                        />
                      ) : (
                        <UserIcon className="w-5 h-5 text-beam-500" />
                      )}
                      <div className="flex flex-col">
                        <span className="text-sm font-semibold text-white">
                          {user.user_metadata?.full_name || "My Account"}
                        </span>
                        <span className="text-xs text-gray-400">{user.email}</span>
                      </div>
                    </div>
                    {isPremium && (
                      <span className="font-[family-name:var(--font-jetbrains-mono)] text-[10px] tracking-[0.14em] px-1.5 py-0.5 rounded-sm text-brass border border-brass/50">
                        PATRON
                      </span>
                    )}
                  </Link>
                  {!isPremium && (
                    <PTButton
                      href="/pricing"
                      variant="gold"
                      size="md"
                      className="w-full"
                      leftIcon={<Sparkles className="w-4 h-4" />}
                    >
                      Become a Patron
                    </PTButton>
                  )}
                </>
              ) : (
                <>
                  <PTButton
                    href="/auth"
                    variant="outline"
                    size="md"
                    className="w-full"
                  >
                    Sign in
                  </PTButton>
                </>
              )}
            </div>
          </div>
        </div>
      </div>
    </header>
  );
}
