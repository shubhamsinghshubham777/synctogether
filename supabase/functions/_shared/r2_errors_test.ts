import { assertEquals } from "jsr:@std/assert@1";
import { isObjectMissing } from "./r2_errors.ts";

Deno.test("only a missing-object answer counts as missing", () => {
  assertEquals(isObjectMissing({ name: "NotFound", $metadata: { httpStatusCode: 404 } }), true);
  assertEquals(isObjectMissing({ name: "NoSuchKey" }), true);
  assertEquals(isObjectMissing({ $metadata: { httpStatusCode: 404 } }), true);
  assertEquals(isObjectMissing({ name: "TimeoutError" }), false);
  assertEquals(isObjectMissing({ $metadata: { httpStatusCode: 403 } }), false);
  assertEquals(isObjectMissing(null), false);
  assertEquals(isObjectMissing(new Error("boom")), false);
});
