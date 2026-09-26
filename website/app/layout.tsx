import type { Metadata, Viewport } from "next";
import { Bricolage_Grotesque, Hanken_Grotesk, JetBrains_Mono } from "next/font/google";
import "./globals.css";
import { Analytics } from "@vercel/analytics/next";
import { Header } from "@/components/Header";
import { Footer } from "@/components/Footer";
import { AnalyticsBeacon } from "@/components/AnalyticsBeacon";
import { SITE_CONFIG } from "@/lib/constants";

// Booth Light faces. globals.css maps the older --font-space-grotesk /
// --font-outfit slots onto these, so existing classes pick them up.
// The opsz axis is what the boards render with: at display sizes Bricolage
// narrows, and without it every headline sets wider and wraps early.
const display = Bricolage_Grotesque({
  variable: "--font-display",
  subsets: ["latin"],
  axes: ["opsz"],
  display: "swap",
});

const body = Hanken_Grotesk({
  variable: "--font-body",
  subsets: ["latin"],
  display: "swap",
});

const jetbrainsMono = JetBrains_Mono({
  variable: "--font-jetbrains-mono",
  subsets: ["latin"],
  display: "swap",
});

export const metadata: Metadata = {
  metadataBase: new URL(SITE_CONFIG.url),
  title: {
    default: "SyncTogether: Watch Movies Together, Even When You're Apart",
    template: "%s | SyncTogether",
  },
  description: SITE_CONFIG.description,
  keywords: [
    "watch movies together long distance",
    "long distance movie night",
    "watch together app",
    "sync video playback",
    "watch party desktop app",
    "watch movies together online",
    "teleparty alternative",
    "syncplay alternative",
    "watch downloaded movies together",
    "synchronized media player",
    "real-time facecams",
    "YouTube sync watch",
  ],
  authors: [{ name: SITE_CONFIG.creatorName }],
  creator: SITE_CONFIG.creatorName,
  openGraph: {
    type: "website",
    locale: "en_US",
    url: SITE_CONFIG.url,
    title: "SyncTogether: Watch Movies Together, Even When You're Apart",
    description: SITE_CONFIG.description,
    siteName: SITE_CONFIG.name,
    images: [
      {
        url: "/og-image.png",
        width: 1200,
        height: 630,
        alt: "SyncTogether: Synchronized Media Playback",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "SyncTogether: Watch Movies Together, Even When You're Apart",
    description: SITE_CONFIG.description,
    images: ["/og-image.png"],
    creator: "@shubhamsingh",
  },
  robots: {
    index: true,
    follow: true,
    googleBot: {
      index: true,
      follow: true,
      "max-video-preview": -1,
      "max-image-preview": "large",
      "max-snippet": -1,
    },
  },
  other: {
    "awin-verification": "Awin",
  },
};

export const viewport: Viewport = {
  colorScheme: "dark",
  themeColor: "#121010",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  const jsonLdOrg = {
    "@context": "https://schema.org",
    "@type": "Organization",
    name: SITE_CONFIG.name,
    url: SITE_CONFIG.url,
    logo: `${SITE_CONFIG.url}/icon.png`,
    sameAs: [SITE_CONFIG.githubRepo],
  };

  const jsonLdApp = {
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    name: "SyncTogether",
    operatingSystem: "macOS 12.0+, Windows 10/11",
    applicationCategory: "MultimediaApplication",
    offers: {
      "@type": "Offer",
      price: "0",
      priceCurrency: "USD",
    },
    description: SITE_CONFIG.description,
  };

  return (
    <html
      lang="en"
      className={`${display.variable} ${body.variable} ${jetbrainsMono.variable} dark`}
      style={{ colorScheme: "dark" }}
      suppressHydrationWarning
    >
      <head>
        <meta name="color-scheme" content="dark" />
        <meta name="theme-color" content="#121010" />
        <meta name="awin-verification" content="Awin" />
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLdOrg) }}
        />
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLdApp) }}
        />
      </head>
      <body className="min-h-screen flex flex-col bg-[#121010] text-gray-100 selection:bg-purple-500/30 selection:text-white">
        <Header />
        <main className="flex-1 pt-[60px] md:pt-[76px]">{children}</main>
        <Footer />
        <Analytics />
        <AnalyticsBeacon />
      </body>
    </html>
  );
}
