/**
 * Display names keyed by `subscriptions.source`. Its own file so client
 * components can import it without pulling in the provider adapters (and with
 * them `crypto`).
 */
export const PROVIDER_LABELS: Record<string, string> = { creem: "Creem" };

export function providerLabel(source: string | null | undefined): string {
  return (source && PROVIDER_LABELS[source]) || "our payment partner";
}
