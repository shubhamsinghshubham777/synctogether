import { createProductionMetricsClient } from "@/lib/supabase/admin";
import { getAllReleases, GitHubRelease } from "@/lib/github";

export interface ReleaseDownloadDetail {
  version: string;
  tagName: string;
  publishedAt: string;
  macDownloads: number;
  winDownloads: number;
  totalDownloads: number;
}

export interface FunnelStage {
  name: string;
  count: number;
  conversionRate: number; // percentage from previous stage
  overallRate: number;    // percentage from top of funnel
}

export interface ServiceQuotaMetric {
  name: string;
  category: "av" | "storage" | "database";
  used: number;
  limit: number;
  unit: string;
  percentage: number;
  status: "healthy" | "warning" | "critical";
  formattedUsed: string;
  formattedLimit: string;
  details: string;
}

export interface InfrastructureHealth {
  dataSource: {
    isProduction: true;
    targetHost: string;
    projectRef?: string;
  };
  services: {
    livekit: ServiceQuotaMetric;
    cloudflareR2: ServiceQuotaMetric;
    supabaseDatabase: ServiceQuotaMetric;
  };
  heartbeats: {
    databaseLatencyMs: number;
    supabaseStatus: "operational" | "degraded" | "down";
    livekitStatus: "operational" | "unconfigured";
    cloudflareR2Status: "operational" | "standby";
  };
  consoleLinks: {
    supabaseUsage: string;
    livekitConsole: string;
    cloudflareR2: string;
  };
}

export function formatBytes(bytes: number, decimals = 2): string {
  if (!bytes || bytes <= 0) return "0 B";
  const k = 1024;
  const dm = decimals < 0 ? 0 : decimals;
  const sizes = ["B", "KB", "MB", "GB", "TB"];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  const val = parseFloat((bytes / Math.pow(k, i)).toFixed(dm));
  return `${val} ${sizes[i]}`;
}

export function calculateQuotaStatus(
  used: number,
  limit: number
): "healthy" | "warning" | "critical" {
  if (limit <= 0) return "healthy";
  const ratio = used / limit;
  if (ratio >= 0.9) return "critical";
  if (ratio >= 0.75) return "warning";
  return "healthy";
}

export interface DashboardMetrics {
  timestamp: string;
  health: {
    supabaseConnected: boolean;
    responseTimeMs: number;
    latestAppVersion: string;
  };
  infrastructure: InfrastructureHealth;

  // 1. Direct Downloads & GitHub Releases
  downloads: {
    directWebsite: {
      total: number;
      last24h: number;
      last7d: number;
      last30d: number;
      macos: number;
      windows: number;
      other: number;
    };
    githubAllTime: {
      totalDownloads: number;
      macDownloads: number;
      winDownloads: number;
      releasesCount: number;
      releases: ReleaseDownloadDetail[];
    };
    combinedTotal: number;
    macTotal: number;
    winTotal: number;
  };

  // 2. Website Unique Visitors & Traffic
  traffic: {
    uniqueVisitorsTotal: number;
    uniqueVisitors24h: number;
    uniqueVisitors7d: number;
    uniqueVisitors30d: number;
    totalPageviews: number;
    pagesPerVisitor: number;
    bounceRatePercent: number;
    topReferrers: { source: string; count: number }[];
    topPages: { path: string; count: number }[];
  };

  // 3. User Tiers & Entitlements
  users: {
    totalRegisteredAccounts: number;
    activePremiumUsers: number;
    registeredFreeUsers: number;
    guestUsers: number;
    totalProfiles: number;
    activeFreeUsers30d: number;
  };

  // 4. DAU and MAU (Business Activity)
  activity: {
    productDau: number;
    productMau: number;
    productStickinessPercent: number;
    websiteDau: number;
    websiteMau: number;
    websiteStickinessPercent: number;
    dauBreakdown: {
      premium: number;
      free: number;
      guest: number;
    };
  };

  // 5. High-Value Product & Financial Metrics
  business: {
    estimatedMrr: number;
    estimatedArr: number;
    payingConversionPercent: number;
    funnel: FunnelStage[];
    rooms: {
      liveRoomsNow: number;
      liveParticipantsNow: number;
      totalRoomsAllTime: number;
      roomsLast7d: number;
      roomsLast30d: number;
      mediaDistribution: {
        youtube: number;
        local: number;
        none: number;
      };
      totalMessagesSent: number;
    };
  };
}

export async function getDashboardMetrics(): Promise<DashboardMetrics> {
  const startTime = Date.now();
  const { client: supabase, host } = createProductionMetricsClient();
  const now = new Date();
  const isoNow = now.toISOString();

  const oneDayAgo = new Date(now.getTime() - 24 * 60 * 60 * 1000).toISOString();
  const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000).toISOString();
  const thirtyDaysAgo = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000).toISOString();

  let supabaseConnected = false;

  // 1. Direct Website Downloads Queries
  let directDownloadsTotal = 0;
  let directDownloads24h = 0;
  let directDownloads7d = 0;
  let directDownloads30d = 0;
  let directMacDownloads = 0;
  let directWinDownloads = 0;
  let directOtherDownloads = 0;

  // 2. Website Visitors & Pageviews Queries
  let uniqueVisitorsTotal = 0;
  let uniqueVisitors24h = 0;
  let uniqueVisitors7d = 0;
  let uniqueVisitors30d = 0;
  let totalPageviews = 0;
  let singlePageVisitors = 0;
  let topReferrers: { source: string; count: number }[] = [];
  let topPages: { path: string; count: number }[] = [];

  // 3. User Tiers & Profiles
  let totalRegisteredAccounts = 0;
  let activePremiumUsers = 0;
  let registeredFreeUsers = 0;
  let guestUsers = 0;
  let totalProfiles = 0;

  // 4. Product Activity (DAU & MAU)
  let productDau = 0;
  let productMau = 0;
  let activeFreeUsers30d = 0;
  const dauBreakdown = { premium: 0, free: 0, guest: 0 };

  // 5. Rooms & Engagement
  let liveRoomsNow = 0;
  let liveParticipantsNow = 0;
  let totalRoomsAllTime = 0;
  let roomsLast7d = 0;
  let roomsLast30d = 0;
  const mediaDistribution = { youtube: 0, local: 0, none: 0 };
  let totalMessagesSent = 0;

  // 6. Resource Quotas & Storage Footprint
  let r2AggregatedUploadBytes = 0;
  let activeRoomMediaBytes = 0;
  let dbBytesUsed = 0;

  try {
    // Parallelize Supabase Queries
    const [
      downloadsTotalRes,
      downloads24hRes,
      downloads7dRes,
      downloads30dRes,
      downloadsMacRes,
      downloadsWinRes,
      visitorsTotalRes,
      visitors24hRes,
      visitors7dRes,
      visitors30dRes,
      pageviewsTotalRes,
      singlePageRes,
      topPagesRes,
      topRefRes,
      profilesRes,
      subscriptionsRes,
      roomsRes,
      liveRoomsRes,
      liveMembersRes,
      messagesRes,
      recentActiveMembers24hRes,
      recentActiveMembers30hRes,
      storageStatsRes,
    ] = await Promise.allSettled([
      supabase.from("website_downloads").select("*", { count: "exact", head: true }),
      supabase.from("website_downloads").select("*", { count: "exact", head: true }).gte("created_at", oneDayAgo),
      supabase.from("website_downloads").select("*", { count: "exact", head: true }).gte("created_at", sevenDaysAgo),
      supabase.from("website_downloads").select("*", { count: "exact", head: true }).gte("created_at", thirtyDaysAgo),
      supabase.from("website_downloads").select("*", { count: "exact", head: true }).eq("platform", "macos"),
      supabase.from("website_downloads").select("*", { count: "exact", head: true }).eq("platform", "windows"),

      supabase.from("website_visitors").select("*", { count: "exact", head: true }),
      supabase.from("website_visitors").select("*", { count: "exact", head: true }).gte("last_seen_at", oneDayAgo),
      supabase.from("website_visitors").select("*", { count: "exact", head: true }).gte("last_seen_at", sevenDaysAgo),
      supabase.from("website_visitors").select("*", { count: "exact", head: true }).gte("last_seen_at", thirtyDaysAgo),
      supabase.from("website_pageviews").select("*", { count: "exact", head: true }),
      supabase.from("website_visitors").select("*", { count: "exact", head: true }).eq("pageviews_count", 1),
      supabase.from("website_pageviews").select("pathname").limit(1000),
      supabase.from("website_visitors").select("first_referrer").not("first_referrer", "is", null).limit(1000),

      supabase.from("profiles").select("id, is_guest, created_at, r2_upload_bytes_7d"),
      supabase.from("subscriptions").select("user_id, tier, current_period_end"),
      supabase.from("rooms").select("id, created_at, media_kind, media_file_size, media_upload_state, ended_at, expires_at"),
      supabase.from("rooms").select("id").is("ended_at", null).gt("expires_at", isoNow),
      supabase.from("room_members").select("room_id, user_id"),
      supabase.from("messages").select("*", { count: "exact", head: true }),

      supabase.from("room_members").select("user_id").gte("joined_at", oneDayAgo),
      supabase.from("room_members").select("user_id").gte("joined_at", thirtyDaysAgo),
      supabase.rpc("get_system_storage_stats"),
    ]);

    supabaseConnected = true;

    // Process Downloads
    if (downloadsTotalRes.status === "fulfilled" && downloadsTotalRes.value.count !== null) {
      directDownloadsTotal = downloadsTotalRes.value.count;
    }
    if (downloads24hRes.status === "fulfilled" && downloads24hRes.value.count !== null) {
      directDownloads24h = downloads24hRes.value.count;
    }
    if (downloads7dRes.status === "fulfilled" && downloads7dRes.value.count !== null) {
      directDownloads7d = downloads7dRes.value.count;
    }
    if (downloads30dRes.status === "fulfilled" && downloads30dRes.value.count !== null) {
      directDownloads30d = downloads30dRes.value.count;
    }
    if (downloadsMacRes.status === "fulfilled" && downloadsMacRes.value.count !== null) {
      directMacDownloads = downloadsMacRes.value.count;
    }
    if (downloadsWinRes.status === "fulfilled" && downloadsWinRes.value.count !== null) {
      directWinDownloads = downloadsWinRes.value.count;
    }
    directOtherDownloads = Math.max(0, directDownloadsTotal - directMacDownloads - directWinDownloads);

    // Process Visitors
    if (visitorsTotalRes.status === "fulfilled" && visitorsTotalRes.value.count !== null) {
      uniqueVisitorsTotal = visitorsTotalRes.value.count;
    }
    if (visitors24hRes.status === "fulfilled" && visitors24hRes.value.count !== null) {
      uniqueVisitors24h = visitors24hRes.value.count;
    }
    if (visitors7dRes.status === "fulfilled" && visitors7dRes.value.count !== null) {
      uniqueVisitors7d = visitors7dRes.value.count;
    }
    if (visitors30dRes.status === "fulfilled" && visitors30dRes.value.count !== null) {
      uniqueVisitors30d = visitors30dRes.value.count;
    }
    if (pageviewsTotalRes.status === "fulfilled" && pageviewsTotalRes.value.count !== null) {
      totalPageviews = pageviewsTotalRes.value.count;
    }
    if (singlePageRes.status === "fulfilled" && singlePageRes.value.count !== null) {
      singlePageVisitors = singlePageRes.value.count;
    }

    // Top Pages
    if (topPagesRes.status === "fulfilled" && topPagesRes.value.data) {
      const pageCounts: Record<string, number> = {};
      for (const item of topPagesRes.value.data) {
        if (item.pathname) {
          pageCounts[item.pathname] = (pageCounts[item.pathname] || 0) + 1;
        }
      }
      topPages = Object.entries(pageCounts)
        .map(([path, count]) => ({ path, count }))
        .sort((a, b) => b.count - a.count)
        .slice(0, 5);
    }

    // Top Referrers
    if (topRefRes.status === "fulfilled" && topRefRes.value.data) {
      const refCounts: Record<string, number> = {};
      for (const item of topRefRes.value.data) {
        if (item.first_referrer) {
          try {
            const domain = new URL(item.first_referrer).hostname.replace(/^www\./, "");
            refCounts[domain] = (refCounts[domain] || 0) + 1;
          } catch {
            refCounts[item.first_referrer] = (refCounts[item.first_referrer] || 0) + 1;
          }
        }
      }
      topReferrers = Object.entries(refCounts)
        .map(([source, count]) => ({ source, count }))
        .sort((a, b) => b.count - a.count)
        .slice(0, 5);
    }

    // Process Users & Subscriptions
    const allProfiles = profilesRes.status === "fulfilled" && profilesRes.value.data ? profilesRes.value.data : [];
    const allSubs = subscriptionsRes.status === "fulfilled" && subscriptionsRes.value.data ? subscriptionsRes.value.data : [];

    totalProfiles = allProfiles.length;
    guestUsers = allProfiles.filter((p) => p.is_guest).length;
    totalRegisteredAccounts = allProfiles.filter((p) => !p.is_guest).length;

    const premiumUserIdSet = new Set<string>();
    for (const sub of allSubs) {
      const isExpired = sub.current_period_end && new Date(sub.current_period_end) <= now;
      if (sub.tier === "premium" && !isExpired) {
        premiumUserIdSet.add(sub.user_id);
      }
    }
    activePremiumUsers = premiumUserIdSet.size;
    registeredFreeUsers = Math.max(0, totalRegisteredAccounts - activePremiumUsers);

    // Process Activity / DAU / MAU
    const active24hUserIds = new Set<string>();
    const active30dUserIds = new Set<string>();

    if (recentActiveMembers24hRes.status === "fulfilled" && recentActiveMembers24hRes.value.data) {
      for (const m of recentActiveMembers24hRes.value.data) {
        active24hUserIds.add(m.user_id);
      }
    }
    if (recentActiveMembers30hRes.status === "fulfilled" && recentActiveMembers30hRes.value.data) {
      for (const m of recentActiveMembers30hRes.value.data) {
        active30dUserIds.add(m.user_id);
      }
    }

    // Check newly registered users in 24h / 30d
    for (const p of allProfiles) {
      const createdTime = new Date(p.created_at).getTime();
      if (createdTime >= new Date(oneDayAgo).getTime()) {
        active24hUserIds.add(p.id);
      }
      if (createdTime >= new Date(thirtyDaysAgo).getTime()) {
        active30dUserIds.add(p.id);
      }
    }

    productDau = active24hUserIds.size;
    productMau = active30dUserIds.size;

    // Segment DAU by tier
    for (const uid of active24hUserIds) {
      const profile = allProfiles.find((p) => p.id === uid);
      if (!profile || profile.is_guest) {
        dauBreakdown.guest += 1;
      } else if (premiumUserIdSet.has(uid)) {
        dauBreakdown.premium += 1;
      } else {
        dauBreakdown.free += 1;
      }
    }

    // Active Free MAU
    for (const uid of active30dUserIds) {
      const profile = allProfiles.find((p) => p.id === uid);
      if (profile && !profile.is_guest && !premiumUserIdSet.has(uid)) {
        activeFreeUsers30d += 1;
      }
    }

    // Process Rooms
    const allRooms = roomsRes.status === "fulfilled" && roomsRes.value.data ? roomsRes.value.data : [];
    totalRoomsAllTime = allRooms.length;

    // Aggregate R2 user uploads from profiles
    for (const p of allProfiles as Array<{ id: string; is_guest: boolean; created_at: string; r2_upload_bytes_7d?: number }>) {
      if (typeof p.r2_upload_bytes_7d === "number") {
        r2AggregatedUploadBytes += p.r2_upload_bytes_7d;
      }
    }

    for (const r of allRooms as Array<{
      id: string;
      created_at: string;
      media_kind: string;
      media_file_size?: number;
      media_upload_state?: string;
      ended_at?: string | null;
      expires_at?: string;
    }>) {
      const createdTime = new Date(r.created_at).getTime();
      if (createdTime >= new Date(sevenDaysAgo).getTime()) roomsLast7d += 1;
      if (createdTime >= new Date(thirtyDaysAgo).getTime()) roomsLast30d += 1;

      if (r.media_kind === "youtube") mediaDistribution.youtube += 1;
      else if (r.media_kind === "local") mediaDistribution.local += 1;
      else mediaDistribution.none += 1;

      if (
        !r.ended_at &&
        r.expires_at &&
        new Date(r.expires_at) > now &&
        r.media_upload_state === "ready" &&
        typeof r.media_file_size === "number"
      ) {
        activeRoomMediaBytes += r.media_file_size;
      }
    }

    if (liveRoomsRes.status === "fulfilled" && liveRoomsRes.value.data) {
      liveRoomsNow = liveRoomsRes.value.data.length;
      const liveRoomIds = new Set(liveRoomsRes.value.data.map((r) => r.id));

      if (liveMembersRes.status === "fulfilled" && liveMembersRes.value.data) {
        liveParticipantsNow = liveMembersRes.value.data.filter((m) => liveRoomIds.has(m.room_id)).length;
      }
    }

    if (messagesRes.status === "fulfilled" && messagesRes.value.count !== null) {
      totalMessagesSent = messagesRes.value.count;
    }

    // Process Storage & Quota Stats from RPC if available
    if (storageStatsRes.status === "fulfilled" && storageStatsRes.value && storageStatsRes.value.data) {
      const rpcData = storageStatsRes.value.data as {
        db_bytes?: number;
        r2_upload_bytes_7d?: number;
        active_r2_media_bytes?: number;
      };
      if (typeof rpcData.db_bytes === "number" && rpcData.db_bytes > 0) {
        dbBytesUsed = rpcData.db_bytes;
      }
      if (typeof rpcData.r2_upload_bytes_7d === "number" && rpcData.r2_upload_bytes_7d > 0) {
        r2AggregatedUploadBytes = rpcData.r2_upload_bytes_7d;
      }
      if (typeof rpcData.active_r2_media_bytes === "number" && rpcData.active_r2_media_bytes > 0) {
        activeRoomMediaBytes = rpcData.active_r2_media_bytes;
      }
    }

    if (dbBytesUsed === 0) {
      // Postgres system catalog base (~32 MB) + row allocation
      dbBytesUsed = (32 * 1024 * 1024) + (totalProfiles * 2048) + (totalRoomsAllTime * 4096) + (totalMessagesSent * 512);
    }
  } catch (err) {
    console.error("Error gathering Supabase metrics:", err);
    supabaseConnected = false;
  }

  // 6. Fetch GitHub Releases Total Downloads
  let githubReleases: GitHubRelease[] = [];
  try {
    githubReleases = await getAllReleases();
  } catch (err) {
    console.error("Error fetching GitHub releases:", err);
  }

  let ghTotalDownloads = 0;
  let ghMacDownloads = 0;
  let ghWinDownloads = 0;
  const releaseDetails: ReleaseDownloadDetail[] = [];

  for (const rel of githubReleases) {
    let relMac = 0;
    let relWin = 0;
    let relTotal = 0;

    for (const a of rel.assets || []) {
      const count = a.download_count || 0;
      relTotal += count;
      if (a.name.endsWith(".dmg") || a.name.includes("macOS")) {
        relMac += count;
      } else if (a.name.endsWith(".exe") || a.name.includes("Windows")) {
        relWin += count;
      }
    }

    ghTotalDownloads += relTotal;
    ghMacDownloads += relMac;
    ghWinDownloads += relWin;

    const rawVersion = rel.name || rel.tag_name;
    const cleanVersion = rawVersion.replace(/^v/, "").replace(/_\d+$/, "");

    releaseDetails.push({
      version: cleanVersion,
      tagName: rel.tag_name,
      publishedAt: rel.published_at,
      macDownloads: relMac,
      winDownloads: relWin,
      totalDownloads: relTotal,
    });
  }

  // Aggregate downloads across both sources
  const combinedTotal = directDownloadsTotal + ghTotalDownloads;
  const combinedMac = directMacDownloads + ghMacDownloads;
  const combinedWin = directWinDownloads + ghWinDownloads;

  // Rate calculations
  const pagesPerVisitor = uniqueVisitorsTotal > 0
    ? Math.round((totalPageviews / uniqueVisitorsTotal) * 10) / 10
    : 0;

  const bounceRatePercent = uniqueVisitorsTotal > 0
    ? Math.round((singlePageVisitors / uniqueVisitorsTotal) * 1000) / 10
    : 0;

  const productStickiness = productMau > 0
    ? Math.round((productDau / productMau) * 1000) / 10
    : 0;

  const websiteStickiness = uniqueVisitors30d > 0
    ? Math.round((uniqueVisitors24h / uniqueVisitors30d) * 1000) / 10
    : 0;

  // Financial Metrics: $5.00/mo flat tier
  const estimatedMrr = activePremiumUsers * 5.0;
  const estimatedArr = estimatedMrr * 12;
  const payingConversionPercent = totalRegisteredAccounts > 0
    ? Math.round((activePremiumUsers / totalRegisteredAccounts) * 1000) / 10
    : 0;

  // Conversion Funnel: Visitors -> Downloads -> Accounts -> Premium
  const funnelBase = Math.max(uniqueVisitorsTotal, 1);
  const funnel: FunnelStage[] = [
    {
      name: "Unique Visitors",
      count: uniqueVisitorsTotal,
      conversionRate: 100,
      overallRate: 100,
    },
    {
      name: "App Downloads",
      count: combinedTotal,
      conversionRate: uniqueVisitorsTotal > 0 ? Math.round((combinedTotal / uniqueVisitorsTotal) * 1000) / 10 : 0,
      overallRate: Math.round((combinedTotal / funnelBase) * 1000) / 10,
    },
    {
      name: "Registered Accounts",
      count: totalRegisteredAccounts,
      conversionRate: combinedTotal > 0 ? Math.round((totalRegisteredAccounts / combinedTotal) * 1000) / 10 : 0,
      overallRate: Math.round((totalRegisteredAccounts / funnelBase) * 1000) / 10,
    },
    {
      name: "Active Premium",
      count: activePremiumUsers,
      conversionRate: totalRegisteredAccounts > 0 ? Math.round((activePremiumUsers / totalRegisteredAccounts) * 1000) / 10 : 0,
      overallRate: Math.round((activePremiumUsers / funnelBase) * 1000) / 10,
    },
  ];

  const latestAppVersion = releaseDetails.length > 0 ? releaseDetails[0].version : "0.11.0";
  const responseTimeMs = Date.now() - startTime;

  const livekitCap = Number(process.env.LIVEKIT_PARTICIPANT_CAP) || 50;
  const livekitPct = Math.min(100, Math.round((liveParticipantsNow / livekitCap) * 100));

  const r2Cap = Number(process.env.CF_R2_STORAGE_CAP_BYTES) || 10 * 1024 * 1024 * 1024;
  const r2TotalUsedBytes = Math.max(r2AggregatedUploadBytes, activeRoomMediaBytes);
  const r2Pct = Math.min(100, Math.round((r2TotalUsedBytes / r2Cap) * 100));

  const dbCap = Number(process.env.SUPABASE_DB_CAP_BYTES) || 500 * 1024 * 1024;
  const dbPct = Math.min(100, Math.round((dbBytesUsed / dbCap) * 100));

  let projectRef: string | undefined;
  if (host.includes(".supabase.co")) {
    projectRef = host.split(".")[0];
  }

  const infrastructure: InfrastructureHealth = {
    dataSource: {
      isProduction: true,
      targetHost: host,
      projectRef,
    },
    services: {
      livekit: {
        name: "LiveKit SFU (Voice & Video Rails)",
        category: "av",
        used: liveParticipantsNow,
        limit: livekitCap,
        unit: "participants",
        percentage: livekitPct,
        status: calculateQuotaStatus(liveParticipantsNow, livekitCap),
        formattedUsed: `${liveParticipantsNow} active`,
        formattedLimit: `${livekitCap} max concurrent`,
        details: `${liveRoomsNow} active rooms • ${liveParticipantsNow} participants connected`,
      },
      cloudflareR2: {
        name: "Cloudflare R2 Media Storage",
        category: "storage",
        used: r2TotalUsedBytes,
        limit: r2Cap,
        unit: "bytes",
        percentage: r2Pct,
        status: calculateQuotaStatus(r2TotalUsedBytes, r2Cap),
        formattedUsed: formatBytes(r2TotalUsedBytes),
        formattedLimit: formatBytes(r2Cap),
        details: `${formatBytes(r2AggregatedUploadBytes)} 7d upload volume • ${formatBytes(activeRoomMediaBytes)} active room media`,
      },
      supabaseDatabase: {
        name: "Supabase Database & Disk",
        category: "database",
        used: dbBytesUsed,
        limit: dbCap,
        unit: "bytes",
        percentage: dbPct,
        status: calculateQuotaStatus(dbBytesUsed, dbCap),
        formattedUsed: formatBytes(dbBytesUsed),
        formattedLimit: formatBytes(dbCap),
        details: `${totalProfiles} user profiles • ${totalRoomsAllTime} rooms • ${totalMessagesSent} messages`,
      },
    },
    heartbeats: {
      databaseLatencyMs: responseTimeMs,
      supabaseStatus: supabaseConnected ? "operational" : "down",
      livekitStatus: process.env.LIVEKIT_URL ? "operational" : "unconfigured",
      cloudflareR2Status: "operational",
    },
    consoleLinks: {
      supabaseUsage: projectRef
        ? `https://supabase.com/dashboard/project/${projectRef}/settings/billing/usage`
        : "https://supabase.com/dashboard",
      livekitConsole: "https://cloud.livekit.io/projects",
      cloudflareR2: "https://dash.cloudflare.com/?to=/:account/r2/overview",
    },
  };

  return {
    timestamp: isoNow,
    health: {
      supabaseConnected,
      responseTimeMs,
      latestAppVersion,
    },
    infrastructure,
    downloads: {
      directWebsite: {
        total: directDownloadsTotal,
        last24h: directDownloads24h,
        last7d: directDownloads7d,
        last30d: directDownloads30d,
        macos: directMacDownloads,
        windows: directWinDownloads,
        other: directOtherDownloads,
      },
      githubAllTime: {
        totalDownloads: ghTotalDownloads,
        macDownloads: ghMacDownloads,
        winDownloads: ghWinDownloads,
        releasesCount: releaseDetails.length,
        releases: releaseDetails,
      },
      combinedTotal,
      macTotal: combinedMac,
      winTotal: combinedWin,
    },
    traffic: {
      uniqueVisitorsTotal,
      uniqueVisitors24h,
      uniqueVisitors7d,
      uniqueVisitors30d,
      totalPageviews,
      pagesPerVisitor,
      bounceRatePercent,
      topReferrers,
      topPages,
    },
    users: {
      totalRegisteredAccounts,
      activePremiumUsers,
      registeredFreeUsers,
      guestUsers,
      totalProfiles,
      activeFreeUsers30d,
    },
    activity: {
      productDau,
      productMau,
      productStickinessPercent: productStickiness,
      websiteDau: uniqueVisitors24h,
      websiteMau: uniqueVisitors30d,
      websiteStickinessPercent: websiteStickiness,
      dauBreakdown,
    },
    business: {
      estimatedMrr,
      estimatedArr,
      payingConversionPercent,
      funnel,
      rooms: {
        liveRoomsNow,
        liveParticipantsNow,
        totalRoomsAllTime,
        roomsLast7d,
        roomsLast30d,
        mediaDistribution,
        totalMessagesSent,
      },
    },
  };
}
