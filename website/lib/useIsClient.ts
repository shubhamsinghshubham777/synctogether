"use client";

import { useSyncExternalStore } from "react";

/** Nothing to subscribe to - the answer never changes within a session. */
const subscribe = () => () => {};

/**
 * False during SSR and on the hydrating render, true afterwards.
 *
 * This is the supported way to read something that genuinely differs between
 * server and client. The `useState(false)` + `useEffect(() => setState(true))`
 * spelling does the same job but trips `react-hooks/set-state-in-effect`,
 * because to React it is indistinguishable from an effect that cascades a
 * second render on every mount. `useSyncExternalStore` says the same thing in
 * the vocabulary React understands: `getServerSnapshot` is what SSR and
 * hydration see, `getSnapshot` is what the client settles on.
 *
 * Use it to gate anything that reads `window` during render, so the markup the
 * server produced and the markup hydration expects still agree.
 */
export function useIsClient(): boolean {
  return useSyncExternalStore(
    subscribe,
    () => true,
    () => false,
  );
}
