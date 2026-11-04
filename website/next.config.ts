import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  images: {
    // Optimized copies live 31 days on Vercel's edge instead of 4 hours, so a quiet
    // site stops re-encoding its images. Nothing invalidates them: if a file under
    // public/ is replaced, rename it (or invalidate the src in Vercel).
    minimumCacheTTL: 2678400,
    remotePatterns: [
      {
        protocol: "https",
        hostname: "lh3.googleusercontent.com",
      },
      {
        protocol: "https",
        hostname: "avatars.githubusercontent.com",
      },
    ],
  },
  async redirects() {
    return [
      {
        source: "/premium",
        destination: "/pricing",
        permanent: true,
      },
      {
        source: "/features",
        destination: "/#features",
        permanent: false,
      },
    ];
  },
};

export default nextConfig;
