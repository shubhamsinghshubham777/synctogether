#!/usr/bin/env node
// ==============================================================================
// SyncTogether: Premium Entitlement Management Core Engine
// ------------------------------------------------------------------------------
// Zero-dependency Node.js CLI engine (Node 18+) that queries Supabase PostgREST
// and Auth Admin APIs to grant, inspect, or revoke premium subscriptions.
// ==============================================================================

import readline from "node:readline";

const ANSI = {
  reset: "\x1b[0m",
  bold: "\x1b[1m",
  cyan: "\x1b[36m",
  green: "\x1b[32m",
  yellow: "\x1b[33m",
  red: "\x1b[31m",
  dim: "\x1b[2m",
  gold: "\x1b[38;5;220m",
};

function info(msg) {
  console.log(`${ANSI.cyan}ℹ ${ANSI.reset}${msg}`);
}

function success(msg) {
  console.log(`${ANSI.green}✔ ${ANSI.reset}${msg}`);
}

function warn(msg) {
  console.log(`${ANSI.yellow}⚠ ${ANSI.reset}${msg}`);
}

function error(msg) {
  console.error(`${ANSI.red}✖ ${ANSI.reset}${msg}`);
}

function banner(title) {
  console.log(`\n${ANSI.bold}${ANSI.cyan}=== ${title} ===${ANSI.reset}\n`);
}

function parseArgs(argv) {
  const args = {
    url: "",
    key: "",
    email: "",
    envName: "Local",
    months: null,
    revoke: false,
    yes: false,
  };

  for (let i = 2; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--url" && i + 1 < argv.length) {
      args.url = argv[++i];
    } else if (arg === "--key" && i + 1 < argv.length) {
      args.key = argv[++i];
    } else if (arg === "--email" && i + 1 < argv.length) {
      args.email = argv[++i];
    } else if (arg === "--env-name" && i + 1 < argv.length) {
      args.envName = argv[++i];
    } else if (arg === "--months" && i + 1 < argv.length) {
      args.months = parseInt(argv[++i], 10);
    } else if (arg === "--revoke") {
      args.revoke = true;
    } else if (arg === "--yes" || arg === "-y") {
      args.yes = true;
    } else if (!arg.startsWith("-") && !args.email) {
      args.email = arg;
    } else if (!arg.startsWith("-") && args.email && args.months === null && !isNaN(parseInt(arg, 10))) {
      args.months = parseInt(arg, 10);
    }
  }

  return args;
}

function askConfirmation(question) {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      rl.close();
      const normalized = answer.trim().toLowerCase();
      resolve(normalized === "y" || normalized === "yes");
    });
  });
}

async function fetchWithRetry(url, options, retries = 2) {
  for (let attempt = 1; attempt <= retries + 1; attempt++) {
    try {
      const res = await fetch(url, options);
      return res;
    } catch (err) {
      if (attempt > retries) throw err;
      await new Promise((r) => setTimeout(r, 500));
    }
  }
}

async function findUserByEmail(baseUrl, serviceKey, email) {
  const cleanEmail = email.trim().toLowerCase();

  // 1. Check public.profiles via PostgREST
  const profileUrl = `${baseUrl}/rest/v1/profiles?email=ilike.${encodeURIComponent(cleanEmail)}&select=id,email,is_guest,display_name`;
  const profileRes = await fetchWithRetry(profileUrl, {
    headers: {
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
    },
  });

  if (!profileRes.ok) {
    const text = await profileRes.text();
    throw new Error(`Failed to query profiles table: HTTP ${profileRes.status} - ${text}`);
  }

  const profiles = await profileRes.json();
  if (Array.isArray(profiles) && profiles.length > 0) {
    return {
      source: "profiles",
      user: profiles[0],
    };
  }

  // 2. Fallback: Search auth.users via Auth Admin API
  let page = 1;
  const perPage = 50;
  while (page <= 10) {
    const authUrl = `${baseUrl}/auth/v1/admin/users?page=${page}&per_page=${perPage}`;
    const authRes = await fetchWithRetry(authUrl, {
      headers: {
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
      },
    });

    if (!authRes.ok) {
      const text = await authRes.text();
      throw new Error(`Failed to query auth admin users: HTTP ${authRes.status} - ${text}`);
    }

    const authData = await authRes.json();
    const users = authData?.users || [];
    if (users.length === 0) break;

    const matched = users.find((u) => u.email && u.email.trim().toLowerCase() === cleanEmail);
    if (matched) {
      return {
        source: "auth",
        user: {
          id: matched.id,
          email: matched.email,
          is_guest: matched.is_anonymous || false,
          display_name:
            matched.user_metadata?.full_name ||
            matched.user_metadata?.name ||
            matched.email.split("@")[0],
        },
      };
    }

    if (users.length < perPage) break;
    page++;
  }

  return null;
}

async function ensureProfileRecord(baseUrl, serviceKey, user) {
  // If user was only found in auth.users, ensure public.profiles row exists
  const upsertUrl = `${baseUrl}/rest/v1/profiles`;
  const res = await fetchWithRetry(upsertUrl, {
    method: "POST",
    headers: {
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
      "Content-Type": "application/json",
      Prefer: "resolution=merge-duplicates,return=representation",
    },
    body: JSON.stringify({
      id: user.id,
      email: user.email,
      is_guest: false,
      display_name: user.display_name || user.email.split("@")[0],
    }),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Failed to ensure profile record: HTTP ${res.status} - ${text}`);
  }
}

async function sanitizeGuestFlag(baseUrl, serviceKey, userId) {
  const updateUrl = `${baseUrl}/rest/v1/profiles?id=eq.${userId}`;
  const res = await fetchWithRetry(updateUrl, {
    method: "PATCH",
    headers: {
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ is_guest: false }),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Failed to update is_guest flag on profile: HTTP ${res.status} - ${text}`);
  }
}

async function getSubscription(baseUrl, serviceKey, userId) {
  const subUrl = `${baseUrl}/rest/v1/subscriptions?user_id=eq.${userId}&select=*`;
  const res = await fetchWithRetry(subUrl, {
    headers: {
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
    },
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Failed to query subscriptions table: HTTP ${res.status} - ${text}`);
  }

  const subs = await res.json();
  return Array.isArray(subs) && subs.length > 0 ? subs[0] : null;
}

async function upsertSubscription(baseUrl, serviceKey, userId, periodEnd) {
  const upsertUrl = `${baseUrl}/rest/v1/subscriptions`;
  const res = await fetchWithRetry(upsertUrl, {
    method: "POST",
    headers: {
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
      "Content-Type": "application/json",
      Prefer: "resolution=merge-duplicates,return=representation",
    },
    body: JSON.stringify({
      user_id: userId,
      tier: "premium",
      source: "admin",
      current_period_end: periodEnd,
      updated_at: new Date().toISOString(),
    }),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Failed to upsert subscription: HTTP ${res.status} - ${text}`);
  }

  const result = await res.json();
  return Array.isArray(result) && result.length > 0 ? result[0] : null;
}

async function revokeSubscription(baseUrl, serviceKey, userId) {
  const delUrl = `${baseUrl}/rest/v1/subscriptions?user_id=eq.${userId}`;
  const res = await fetchWithRetry(delUrl, {
    method: "DELETE",
    headers: {
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
    },
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Failed to delete subscription: HTTP ${res.status} - ${text}`);
  }
}

async function main() {
  const args = parseArgs(process.argv);

  if (!args.url || !args.key || !args.email) {
    error("Missing required arguments (--url, --key, or --email).");
    console.log(
      "Usage: node grant-premium-core.mjs --url <URL> --key <KEY> --email <EMAIL> [--months <N>] [--revoke] [--yes]"
    );
    process.exit(1);
  }

  const cleanBaseUrl = args.url.replace(/\/+$/, "");
  const targetHost = new URL(cleanBaseUrl).hostname;

  banner(`SyncTogether Premium Entitlement Manager [${args.envName.toUpperCase()}]`);

  info(`Target Environment: ${ANSI.bold}${args.envName}${ANSI.reset} (${targetHost})`);
  info(`Searching for user:  ${ANSI.bold}${args.email}${ANSI.reset}...`);

  // 1. Find the user
  const found = await findUserByEmail(cleanBaseUrl, args.key, args.email);
  if (!found) {
    error(`User with email "${args.email}" was not found in Supabase auth or profiles.`);
    console.log(
      `${ANSI.yellow}Note: The user must sign up or create an account before premium access can be granted.${ANSI.reset}`
    );
    process.exit(1);
  }

  const user = found.user;
  success(`Found user: ${ANSI.bold}${user.display_name || user.email}${ANSI.reset} (ID: ${user.id})`);

  // 2. Inspect current subscription
  const currentSub = await getSubscription(cleanBaseUrl, args.key, user.id);
  const currentTier = currentSub?.tier || "free";
  const currentExp = currentSub?.current_period_end
    ? new Date(currentSub.current_period_end).toLocaleString()
    : currentSub
      ? "Lifetime / No Expiration"
      : "None (Free tier)";

  console.log(`\n${ANSI.dim}Current Entitlement State:${ANSI.reset}`);
  console.log(`  • User ID:          ${user.id}`);
  console.log(`  • Email:            ${user.email}`);
  console.log(`  • Current Tier:     ${ANSI.bold}${currentTier}${ANSI.reset}`);
  console.log(`  • Current Source:   ${currentSub?.source || "n/a"}`);
  console.log(`  • Current Expiry:   ${currentExp}\n`);

  // 3. Handle Revoke
  if (args.revoke) {
    if (!args.yes) {
      const confirm = await askConfirmation(
        `${ANSI.yellow}Are you sure you want to REVOKE premium access for ${user.email} on ${args.envName}? (y/N): ${ANSI.reset}`
      );
      if (!confirm) {
        warn("Operation cancelled by user.");
        process.exit(0);
      }
    }

    info("Revoking premium subscription...");
    await revokeSubscription(cleanBaseUrl, args.key, user.id);
    success(`Premium access successfully revoked for ${ANSI.bold}${user.email}${ANSI.reset}.`);
    console.log(`User tier reverted to: ${ANSI.bold}free${ANSI.reset}.\n`);
    process.exit(0);
  }

  // 4. Calculate period end
  let periodEndIso = null;
  let durationDescription = "Lifetime (Permanent)";

  if (args.months && args.months > 0) {
    const futureDate = new Date();
    futureDate.setMonth(futureDate.getMonth() + args.months);
    periodEndIso = futureDate.toISOString();
    durationDescription = `${args.months} month(s) (Expires: ${futureDate.toLocaleDateString()})`;
  }

  // 5. Confirmation for Production or non-yes executions
  if (!args.yes) {
    const promptMsg =
      args.envName.toLowerCase() === "production"
        ? `${ANSI.red}${ANSI.bold}CONFIRM PRODUCTION CHANGE:${ANSI.reset} Grant ${durationDescription} Premium to ${user.email}? (y/N): `
        : `Grant ${durationDescription} Premium to ${user.email}? (y/N): `;

    const confirm = await askConfirmation(promptMsg);
    if (!confirm) {
      warn("Operation cancelled by user.");
      process.exit(0);
    }
  }

  // 6. Ensure profile exists and guest flag is sanitized
  await ensureProfileRecord(cleanBaseUrl, args.key, user);
  if (user.is_guest) {
    info("User is currently marked as guest. Upgrading profile to full authenticated user...");
    await sanitizeGuestFlag(cleanBaseUrl, args.key, user.id);
  }

  // 7. Upsert subscription
  info("Upserting subscription to 'premium'...");
  const updatedSub = await upsertSubscription(cleanBaseUrl, args.key, user.id, periodEndIso);

  // 8. Verification & celebratory receipt
  console.log("\n" + ANSI.gold + "==================================================");
  console.log("       SYNC TOGETHER PREMIUM ACCESS GRANTED! 👑");
  console.log("==================================================" + ANSI.reset);
  console.log(`  User Email:       ${ANSI.bold}${user.email}${ANSI.reset}`);
  console.log(`  User ID:          ${user.id}`);
  console.log(`  Environment:      ${args.envName} (${targetHost})`);
  console.log(`  Entitlement Tier: ${ANSI.green}${ANSI.bold}premium${ANSI.reset}`);
  console.log(`  Source:           ${updatedSub?.source || "admin"}`);
  console.log(`  Access Duration:  ${ANSI.bold}${durationDescription}${ANSI.reset}`);
  console.log(
    `  Realtime Sync:    ${ANSI.cyan}Broadcast to all connected clients & web portals${ANSI.reset}`
  );
  console.log(ANSI.gold + "==================================================\n" + ANSI.reset);
  success("Entitlement grant complete.");
}

main().catch((err) => {
  error(`Execution failed: ${err.message}`);
  process.exit(1);
});
