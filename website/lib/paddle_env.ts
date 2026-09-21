/**
 * One place for the Paddle environment, because there were three and they
 * disagreed.
 *
 * `usePremiumCheckout` fell back to the placeholder ids `"pri_monthly_default"`
 * and `"pri_annual_default"`, while `/api/paddle/prices` fell back to a pair of
 * real-looking `pri_01m02w...` ids. So the price shown and the price charged
 * resolved through different defaults, and a missing environment variable
 * surfaced as an opaque failure inside Paddle's overlay rather than as anything
 * anybody could debug.
 */

export function isProductionPaddle(): boolean {
  return process.env.NEXT_PUBLIC_PADDLE_ENVIRONMENT === "production";
}

export function paddleApiHost(): string {
  return isProductionPaddle()
    ? "https://api.paddle.com"
    : "https://sandbox-api.paddle.com";
}

/** Placeholder keys ship in `.env.example`; treat them as absent. */
export function isPaddleApiKeyUsable(): boolean {
  const key = process.env.PADDLE_API_KEY;
  return Boolean(key && key.trim() !== "" && !key.includes("xxx"));
}

/**
 * Static `process.env.NEXT_PUBLIC_*` references, never computed keys: Next.js
 * inlines these into the client bundle by literal textual match at build time,
 * so `process.env[`NEXT_PUBLIC_${name}`]` resolves to undefined in the browser.
 */
function resolve(
  configured: string | undefined,
  name: "MONTHLY" | "ANNUAL"
): string {
  if (configured && !configured.includes("xxx")) return configured;
  if (isProductionPaddle()) {
    // Loudly, rather than opening a checkout against an id nobody chose.
    throw new Error(
      `PADDLE_${name}_PRICE_ID is not configured; refusing to open a production checkout.`
    );
  }
  return `pri_${name.toLowerCase()}_unconfigured`;
}

export const paddlePriceIds = {
  get monthly() {
    return resolve(
      process.env.NEXT_PUBLIC_PADDLE_MONTHLY_PRICE_ID ||
        process.env.PADDLE_MONTHLY_PRICE_ID,
      "MONTHLY"
    );
  },
  get annual() {
    return resolve(
      process.env.NEXT_PUBLIC_PADDLE_ANNUAL_PRICE_ID ||
        process.env.PADDLE_ANNUAL_PRICE_ID,
      "ANNUAL"
    );
  },
};
