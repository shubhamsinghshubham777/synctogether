import { SITE_CONFIG } from "@/lib/constants";
import { COMPARISONS, FACTS, GUIDES } from "../facts/facts";

// Served as plain text for answer engines (https://llmstxt.org). Built from the
// same FACTS the /facts page renders, so the two cannot disagree.
export const dynamic = "force-static";

export function GET() {
  const body = [
    `# ${SITE_CONFIG.name}`,
    "",
    `> ${SITE_CONFIG.description}`,
    "",
    "## Facts",
    "",
    ...FACTS.map(({ label, value }) => `- ${label}: ${value}`),
    "",
    "## Pages",
    "",
    `- [Facts](${SITE_CONFIG.url}/facts): the facts above, on one page`,
    `- [Download](${SITE_CONFIG.url}/download): Mac App Store and Microsoft Store links`,
    `- [Pricing](${SITE_CONFIG.url}/pricing): what each plan allows`,
    `- [FAQ](${SITE_CONFIG.url}/faq): common questions`,
    ...COMPARISONS.map(({ name, path }) => `- [vs ${name}](${SITE_CONFIG.url}${path}): honest comparison`),
    ...GUIDES.map(({ name, path }) => `- [${name}](${SITE_CONFIG.url}${path}): guide`),
    "",
  ].join("\n");

  return new Response(body, { headers: { "content-type": "text/plain; charset=utf-8" } });
}
