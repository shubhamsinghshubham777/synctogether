// Whether an R2/S3 error says the object is not there (as opposed to a network
// or permission failure, which says nothing about the object).
export function isObjectMissing(err: unknown): boolean {
  const e = err as { name?: string; Code?: string; $metadata?: { httpStatusCode?: number } } | null;
  if (!e) return false;
  return e.$metadata?.httpStatusCode === 404 || e.name === "NotFound" || e.name === "NoSuchKey" ||
    e.Code === "NoSuchKey";
}
