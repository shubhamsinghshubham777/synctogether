import { PRICING_TIERS } from "./constants.ts";

export type ResolvableTier = "guest" | "free" | "premium";

const TIER_ORDER: ResolvableTier[] = ["guest", "free", "premium"];

/**
 * Cheapest tier whose room can hold `people` members for `minutes` of total
 * session length. Every threshold is read from PRICING_TIERS - lib/constants.ts
 * is the single source of truth, tuned independently of the Flutter app's own
 * tier_limits table, so nothing here may hardcode 4/8/16 or 60/240/1440.
 */
export function cheapestTierFor(people: number, minutes: number): ResolvableTier | null {
  for (const tier of TIER_ORDER) {
    const limits = PRICING_TIERS[tier].limits;
    if (limits.members >= people && limits.totalSessionMinutes >= minutes) {
      return tier;
    }
  }
  return null;
}
