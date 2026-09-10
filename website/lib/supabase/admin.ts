import { createClient } from "@supabase/supabase-js";

export class ProductionCredentialsError extends Error {
  public readonly code: "LOOPBACK_DETECTED" | "MISSING_CREDENTIALS" | "DEMO_KEY_DETECTED" | "INVALID_URL";
  public readonly resolution: string;

  constructor(
    message: string,
    code: "LOOPBACK_DETECTED" | "MISSING_CREDENTIALS" | "DEMO_KEY_DETECTED" | "INVALID_URL",
    resolution: string
  ) {
    super(message);
    this.name = "ProductionCredentialsError";
    this.code = code;
    this.resolution = resolution;
  }
}

const LOCAL_DEMO_SERVICE_KEY =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU";

export function isLoopbackHost(hostname: string): boolean {
  let cleanHost = hostname.toLowerCase().trim();
  if (cleanHost.startsWith("[") && cleanHost.endsWith("]")) {
    cleanHost = cleanHost.slice(1, -1);
  }
  // Strip port only if not an IPv6 address (which contains double colons)
  if (cleanHost.includes(":") && !cleanHost.includes("::")) {
    cleanHost = cleanHost.split(":")[0];
  }
  return (
    cleanHost === "localhost" ||
    cleanHost === "127.0.0.1" ||
    cleanHost === "0.0.0.0" ||
    cleanHost === "::1" ||
    cleanHost.endsWith(".localhost") ||
    cleanHost.endsWith(".local")
  );
}

export function validateProductionCredentials(
  overrideUrl?: string,
  overrideKey?: string
):
  | { valid: true; url: string; key: string; host: string }
  | {
      valid: false;
      code: "LOOPBACK_DETECTED" | "MISSING_CREDENTIALS" | "DEMO_KEY_DETECTED" | "INVALID_URL";
      message: string;
      resolution: string;
    } {
  const url =
    overrideUrl ||
    process.env.PROD_SUPABASE_URL ||
    process.env.NEXT_PUBLIC_SUPABASE_URL;

  const key =
    overrideKey ||
    process.env.PROD_SUPABASE_SERVICE_ROLE_KEY ||
    process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!url || url.trim().length === 0 || !key || key.trim().length === 0) {
    return {
      valid: false,
      code: "MISSING_CREDENTIALS",
      message:
        "Production Supabase credentials are missing. The metrics dashboard strictly requires production data and denies operating on unconfigured environments.",
      resolution:
        "Add PROD_SUPABASE_URL (e.g. https://<project-ref>.supabase.co) and PROD_SUPABASE_SERVICE_ROLE_KEY to website/.env.local.",
    };
  }

  let parsed: URL;
  try {
    parsed = new URL(url.trim());
  } catch {
    return {
      valid: false,
      code: "INVALID_URL",
      message: `The provided Supabase URL is not a valid URL: "${url}".`,
      resolution:
        "Ensure PROD_SUPABASE_URL starts with https:// and has a valid hostname.",
    };
  }

  if (isLoopbackHost(parsed.hostname)) {
    return {
      valid: false,
      code: "LOOPBACK_DETECTED",
      message: `Local loopback address detected (${parsed.hostname}). The admin metrics dashboard is strictly forbidden from displaying localhost/seed data to protect business decision integrity.`,
      resolution:
        "Set PROD_SUPABASE_URL and PROD_SUPABASE_SERVICE_ROLE_KEY in website/.env.local pointing to your live production Supabase instance.",
    };
  }

  if (key.trim() === LOCAL_DEMO_SERVICE_KEY || key.trim().includes("supabase-demo")) {
    return {
      valid: false,
      code: "DEMO_KEY_DETECTED",
      message:
        "Local development demo service_role key was detected. A live production service_role key is required.",
      resolution:
        "Copy your production service_role key from your Supabase Project Settings -> API and set PROD_SUPABASE_SERVICE_ROLE_KEY in website/.env.local.",
    };
  }

  return {
    valid: true,
    url: url.trim(),
    key: key.trim(),
    host: parsed.hostname,
  };
}

export function createProductionMetricsClient() {
  const check = validateProductionCredentials();
  if (!check.valid) {
    throw new ProductionCredentialsError(check.message, check.code, check.resolution);
  }

  return {
    client: createClient(check.url, check.key, {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    }),
    host: check.host,
    url: check.url,
  };
}

export function createAdminClient() {
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL || "http://127.0.0.1:54321";
  const supabaseServiceKey =
    process.env.SUPABASE_SERVICE_ROLE_KEY || LOCAL_DEMO_SERVICE_KEY;

  return createClient(supabaseUrl, supabaseServiceKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}

