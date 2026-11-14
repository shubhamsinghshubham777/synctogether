import type { Metadata } from "next";
import { headers } from "next/headers";
import { notFound } from "next/navigation";
import Link from "next/link";
import { ArrowLeft, Smartphone } from "lucide-react";
import { isAuthorizedLocalAccess } from "@/lib/admin-guard";
import { createAdminClient } from "@/lib/supabase/admin";
import { seatTarget } from "@/lib/android-testers";

export const metadata: Metadata = {
  title: "Android Testers",
  description: "Internal list of Android early-access sign-ups",
  robots: { index: false, follow: false },
};

export const dynamic = "force-dynamic";

type Row = { id: number; email: string; source: string; created_at: string };

export default async function AndroidTestersPage() {
  const reqHeaders = await headers();
  if (!isAuthorizedLocalAccess({ headers: reqHeaders })) {
    notFound();
  }

  const { data, error } = await createAdminClient()
    .from("android_testers")
    .select("id, email, source, created_at")
    .order("id", { ascending: true })
    .limit(2000);
  const rows = (data ?? []) as Row[];
  const target = seatTarget(process.env.ANDROID_SEAT_TARGET);
  const bySource = new Map<string, number>();
  for (const r of rows) bySource.set(r.source, (bySource.get(r.source) ?? 0) + 1);
  // One line, comma separated: what the Play Console's tester list takes on paste.
  const paste = rows.map((r) => r.email).join(", ");

  return (
    <div className="min-h-screen bg-booth text-screen p-4 sm:p-8 space-y-6 max-w-[1100px] mx-auto">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 border-b border-rail pb-4">
        <div className="flex items-center gap-3">
          <div className="p-2.5 rounded-md bg-seat border border-rail text-screen">
            <Smartphone className="w-6 h-6" aria-hidden="true" />
          </div>
          <div>
            <h1 className="text-xl font-bold tracking-tight text-screen">Android Testers</h1>
            <p className="text-xs text-gray-400 font-mono">
              {rows.length} of {target} seats &bull; Google needs 12 opted in for 14 days
            </p>
          </div>
        </div>
        <Link
          href="/admin"
          className="px-3 py-1.5 rounded-md bg-aisle hover:bg-aisle/80 text-xs font-mono text-gray-400 hover:text-white border border-rail flex items-center gap-1.5 transition-colors w-fit"
        >
          <ArrowLeft className="w-3.5 h-3.5" aria-hidden="true" />
          Operator Booth
        </Link>
      </div>

      {error ? (
        <p className="text-sm text-signal">Could not load the list: {error.message}</p>
      ) : rows.length === 0 ? (
        <p className="text-sm text-gray-400">Nobody has saved a seat yet.</p>
      ) : (
        <>
          <p className="text-xs font-mono text-gray-400">
            {[...bySource].map(([k, v]) => `${k} ${v}`).join(" · ")}
          </p>

          <section className="space-y-2">
            <h2 className="text-xs font-mono tracking-[0.14em] uppercase text-gray-500">
              Paste into Play Console
            </h2>
            <textarea
              readOnly
              value={paste}
              rows={3}
              className="w-full rounded-md bg-seat border border-rail p-3 text-xs font-mono text-gray-300"
            />
          </section>

          <div className="overflow-x-auto rounded-md border border-rail">
            <table className="w-full text-sm">
              <thead className="bg-seat text-left text-xs font-mono uppercase tracking-[0.1em] text-gray-500">
                <tr>
                  <th className="px-3 py-2">Seat</th>
                  <th className="px-3 py-2">Email</th>
                  <th className="px-3 py-2">From</th>
                  <th className="px-3 py-2">Signed up</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r, i) => (
                  <tr key={r.id} className="border-t border-rail">
                    <td className="px-3 py-2 font-mono text-gray-400">{String(i + 1).padStart(2, "0")}</td>
                    <td className="px-3 py-2 text-screen">{r.email}</td>
                    <td className="px-3 py-2 font-mono text-gray-400">{r.source}</td>
                    <td className="px-3 py-2 font-mono text-gray-400">
                      {new Date(r.created_at).toLocaleString("en-GB", { dateStyle: "medium", timeStyle: "short" })}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}
    </div>
  );
}
