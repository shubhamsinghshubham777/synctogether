import { MetadataRoute } from "next";
import { SITE_CONFIG } from "@/lib/constants";

export default function robots(): MetadataRoute.Robots {
  const baseUrl = SITE_CONFIG.url;

  return {
    rules: {
      userAgent: "*",
      allow: "/",
      // `/r/` is an unguessable URL the owner shared with particular
      // people - it is not content, and indexing one would outlive any
      // later change of mind. `/join/` is a capability, not a page.
      disallow: [
        "/api/",
        "/auth/callback",
        "/account",
        "/internal",
        "/admin",
        "/r/",
        "/join/",
      ],
    },
    sitemap: `${baseUrl}/sitemap.xml`,
  };
}
