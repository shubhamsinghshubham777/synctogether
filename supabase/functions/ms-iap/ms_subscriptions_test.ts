import { assertEquals } from "jsr:@std/assert@1";
import { decodeJwtPayload, entitlementFromRecurrences, keyBindsTo } from "./ms_subscriptions.ts";

const b64 = (o: unknown) => btoa(JSON.stringify(o)).replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_");
const now = Date.parse("2026-10-15T00:00:00Z");
const ours = new Set(["prod"]);

Deno.test("key binds only to the id it was minted for", () => {
  const key = `h.${b64({ sub: "x", pub: "AAAA-BBBB" })}.s`;
  const payload = decodeJwtPayload(key);
  assertEquals(keyBindsTo(payload, "aaaa-bbbb"), true);
  assertEquals(keyBindsTo(payload, "cccc"), false);
  assertEquals(keyBindsTo(decodeJwtPayload("garbage"), "aaaa-bbbb"), false);
});

Deno.test("an active subscription of ours is entitled until its expiry", () => {
  const e = entitlementFromRecurrences(
    [{ id: "mdr:1", productId: "prod", skuId: "0010", recurrenceState: "Active", expirationTime: "2026-11-01T00:00:00Z", autoRenew: true }],
    ours,
    now,
  );
  assertEquals(e?.purchaseId, "mdr:1");
  assertEquals(e?.expiresAt, "2026-11-01T00:00:00.000Z");
  assertEquals(e?.revokedAt, null);
  assertEquals(e?.autoRenew, true);
});

Deno.test("strangers, and items we cannot date or understand, are ignored", () => {
  assertEquals(
    entitlementFromRecurrences(
      [
        { id: "a", productId: "other", recurrenceState: "Active", expirationTime: "2027-01-01T00:00:00Z" },
        { id: "b", productId: "prod", recurrenceState: "Active" },
        { id: "c", productId: "prod", recurrenceState: "Mystery", expirationTime: "2027-01-01T00:00:00Z" },
        { productId: "prod", recurrenceState: "Active", expirationTime: "2027-01-01T00:00:00Z" },
      ],
      ours,
      now,
    ),
    null,
  );
  assertEquals(entitlementFromRecurrences([], ours, now), null);
});

Deno.test("a healthy subscription gets no grace on top of its expiry", () => {
  const e = entitlementFromRecurrences(
    [{
      id: "g",
      productId: "prod",
      recurrenceState: "Active",
      expirationTime: "2026-11-21T00:00:00Z",
      expirationTimeWithGrace: "2026-11-24T00:00:00Z",
    }],
    ours,
    now,
  );
  assertEquals(e?.expiresAt, "2026-11-21T00:00:00.000Z");
});

Deno.test("billing retry runs to the end of the grace period", () => {
  const e = entitlementFromRecurrences(
    [{
      id: "d",
      productId: "prod",
      recurrenceState: "InDunning",
      expirationTime: "2026-10-14T00:00:00Z",
      expirationTimeWithGrace: "2026-10-21T00:00:00Z",
    }],
    ours,
    now,
  );
  assertEquals(e?.expiresAt, "2026-10-21T00:00:00.000Z");
  assertEquals(e?.revokedAt, null);
});

Deno.test("cancelled and failed are dated revocations; inactive is just an expiry", () => {
  const cancelled = entitlementFromRecurrences(
    [{ id: "a", productId: "prod", recurrenceState: "Canceled", expirationTime: "2026-12-01T00:00:00Z", cancellationDate: "2026-10-10T00:00:00Z" }],
    ours,
    now,
  );
  assertEquals(cancelled?.revokedAt, "2026-10-10T00:00:00.000Z");
  const failed = entitlementFromRecurrences([{ id: "a", productId: "prod", recurrenceState: "Failed" }], ours, now);
  assertEquals(failed?.revokedAt, new Date(now).toISOString());
  const inactive = entitlementFromRecurrences(
    [{ id: "a", productId: "prod", recurrenceState: "Inactive", expirationTime: "2026-10-01T00:00:00Z" }],
    ours,
    now,
  );
  assertEquals(inactive?.revokedAt, null);
  assertEquals(inactive?.expiresAt, "2026-10-01T00:00:00.000Z");
});

Deno.test("a live subscription beats a later-ending dead one, then the latest-ending wins", () => {
  const e = entitlementFromRecurrences(
    [
      { id: "old", productId: "prod", recurrenceState: "Canceled", expirationTime: "2027-06-01T00:00:00Z" },
      { id: "short", productId: "prod", recurrenceState: "Active", expirationTime: "2026-11-01T00:00:00Z" },
      { id: "long", productId: "prod", recurrenceState: "Active", expirationTime: "2026-12-01T00:00:00Z" },
    ],
    ours,
    now,
  );
  assertEquals(e?.purchaseId, "long");
});

Deno.test("a perpetual subscription never expires", () => {
  const e = entitlementFromRecurrences([{ id: "p", productId: "prod", recurrenceState: "None" }], ours, now);
  assertEquals(e?.expiresAt, "9999-12-31T23:59:59.000Z");
  assertEquals(e?.revokedAt, null);
});
