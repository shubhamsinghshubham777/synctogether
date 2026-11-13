"use client";

import { useEffect, useMemo, useRef, useState, useTransition } from "react";
import {
  DEFAULT_FILTERS,
  MIN_REASON_CHARS,
  REASON_STARTERS,
  STARTER_LABELS,
  cardTitle,
  checkOriginal,
  duplicatePreview,
  filterRows,
  fixedFromError,
  normalizeVersion,
  indexById,
  knownVersions,
  laneOf,
  moveNeeds,
  nonSpaceLength,
  publicTitleOf,
  reasonError,
  sameCounts,
  searchOriginals,
  wontFixPreview,
  type BoardFilters,
  type BugLane,
  type BugRow,
  type MoveTarget,
} from "@/lib/bug_board_logic";
import {
  closeWontFixAction,
  markDuplicateAction,
  markFixedAction,
  moveBugAction,
  type BoardResult,
} from "./actions";

type Dialog = { kind: "fixed" | "wontfix" | "duplicate"; code: string } | null;

const LANES: { id: BugLane; label: string; tone: string }[] = [
  { id: "received", label: "RECEIVED", tone: "border-aisle text-gray-300" },
  { id: "looking", label: "LOOKING INTO IT", tone: "border-beam-500/40 text-beam-500" },
  { id: "fixed", label: "FIXED", tone: "border-cue/40 text-cue" },
];

const MOVE_LABELS: Record<MoveTarget, string> = {
  received: "Received",
  looking: "Looking into it",
  fixed: "Fixed…",
  wontfix: "Won't fix…",
  duplicate: "Duplicate…",
};

const inputCls =
  "w-full rounded-md border border-rail bg-booth px-3 py-2 text-sm text-screen placeholder:text-gray-500 focus:border-beam-500 focus:outline-none";
const chipCls =
  "h-8 rounded-md border border-rail bg-transparent px-3 text-xs font-medium text-gray-300 hover:border-gray-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-beam-500";
const btnLit =
  "h-10 rounded-md bg-beam-500 px-4 text-sm font-semibold text-[var(--pt-on-beam)] disabled:cursor-not-allowed disabled:bg-aisle disabled:text-gray-600";
const btnPlain =
  "h-10 rounded-md border border-gray-600 bg-transparent px-4 text-sm font-semibold text-screen hover:border-gray-400";

export function BugBoardClient({
  rows,
  releases,
}: {
  rows: BugRow[];
  releases: { value: string; label: string }[];
}) {
  const [filters, setFilters] = useState<BoardFilters>(DEFAULT_FILTERS);
  const [dialog, setDialog] = useState<Dialog>(null);
  const [error, setError] = useState<string | null>(null);
  const [dragging, setDragging] = useState<string | null>(null);
  const [over, setOver] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  const byId = useMemo(() => indexById(rows), [rows]);
  const same = useMemo(() => sameCounts(rows), [rows]);
  const versions = useMemo(() => knownVersions(rows), [rows]);
  const visible = useMemo(() => filterRows(rows, filters), [rows, filters]);
  const byCode = useMemo(() => new Map(rows.map((r) => [r.code, r])), [rows]);

  const lanes = useMemo(() => {
    const out: Record<BugLane | "closed", BugRow[]> = { received: [], looking: [], fixed: [], closed: [] };
    for (const r of visible) out[laneOf(r, byId)].push(r);
    return out;
  }, [visible, byId]);

  const openCount = rows.filter((r) => !r.duplicateOf && (r.status === "received" || r.status === "looking")).length;
  const fixedWeek = rows.filter((r) => r.status === "fixed" && !r.duplicateOf).length;

  function run(action: () => Promise<BoardResult>, after?: () => void) {
    setError(null);
    startTransition(async () => {
      const res = await action();
      if (res.ok) after?.();
      else setError(res.error);
    });
  }

  /** The one place a target decides whether a card may move now or needs a form first. */
  function requestMove(code: string, target: MoveTarget) {
    const row = byCode.get(code);
    if (!row) return;
    const need = moveNeeds(target);
    if (need === "none") {
      if (laneOf(row, byId) === target && !row.duplicateOf && row.status === target) return;
      run(() => moveBugAction(code, target as "received" | "looking"));
      return;
    }
    setError(null);
    setDialog({ kind: need === "version" ? "fixed" : need === "reason" ? "wontfix" : "duplicate", code });
  }

  function dropOn(target: MoveTarget) {
    const code = dragging;
    setDragging(null);
    setOver(null);
    if (code) requestMove(code, target);
  }

  const dropProps = (target: MoveTarget) => ({
    onDragOver: (e: React.DragEvent) => {
      if (!dragging) return;
      e.preventDefault();
      setOver(target);
    },
    onDragLeave: () => setOver((o) => (o === target ? null : o)),
    onDrop: (e: React.DragEvent) => {
      e.preventDefault();
      dropOn(target);
    },
  });

  const active = dialog ? byCode.get(dialog.code) : undefined;

  return (
    <div className="space-y-5" aria-busy={pending}>
      {/* Filters */}
      <div className="flex flex-wrap items-center gap-3">
        <input
          type="search"
          aria-label="Search reports"
          placeholder="Search code, note or version"
          value={filters.search}
          onChange={(e) => setFilters({ ...filters, search: e.target.value })}
          className={`${inputCls} !w-80`}
        />
        <select
          aria-label="Category"
          value={filters.category}
          onChange={(e) => setFilters({ ...filters, category: e.target.value })}
          className={`${chipCls} !h-9 bg-booth`}
        >
          <option value="all">Category: all</option>
          {["video", "sound", "sync", "chat", "camera", "other"].map((c) => (
            <option key={c} value={c}>
              {c[0].toUpperCase() + c.slice(1)}
            </option>
          ))}
        </select>
        <select
          aria-label="App version"
          value={filters.version}
          onChange={(e) => setFilters({ ...filters, version: e.target.value })}
          className={`${chipCls} !h-9 bg-booth`}
        >
          <option value="all">Version: all</option>
          {versions.map((v) => (
            <option key={v} value={v}>
              Version: {v}
            </option>
          ))}
        </select>
        <button
          type="button"
          aria-pressed={filters.groupDuplicates}
          onClick={() => setFilters({ ...filters, groupDuplicates: !filters.groupDuplicates })}
          className={`${chipCls} !h-9 ${filters.groupDuplicates ? "!border-beam-500 !text-beam-200" : ""}`}
        >
          Group duplicates
        </button>
        <div className="ml-auto font-mono text-[11px] tracking-[0.14em] text-gray-500">
          {openCount} OPEN &middot; {fixedWeek} FIXED
        </div>
      </div>

      {error ? (
        <div role="alert" className="rounded-md border border-signal bg-seat px-4 py-3 text-sm text-gray-200">
          {error}
        </div>
      ) : null}

      {/* Lanes + close-as zones */}
      <div className="grid gap-3.5 lg:grid-cols-[1fr_1fr_1fr_210px]">
        {LANES.map((lane) => (
          <section
            key={lane.id}
            aria-label={lane.label}
            {...dropProps(lane.id)}
            className={`flex min-h-[320px] flex-col gap-2.5 rounded-md border bg-seat/40 p-3 ${lane.tone} ${
              over === lane.id ? "!border-beam-500 bg-seat" : ""
            }`}
          >
            <h2 className="flex items-center justify-between font-mono text-[11px] font-normal tracking-[0.12em]">
              <span>{lane.label}</span>
              <span className="text-gray-400">{lanes[lane.id].length}</span>
            </h2>
            {lanes[lane.id].map((row) => (
              <Card
                key={row.id}
                row={row}
                same={same.get(row.id) ?? 0}
                follower={row.duplicateOf ? byId.get(row.duplicateOf)?.code : undefined}
                lane={lane.id}
                disabled={pending}
                onDragStart={() => setDragging(row.code)}
                onDragEnd={() => {
                  setDragging(null);
                  setOver(null);
                }}
                onMove={(t) => requestMove(row.code, t)}
                followers={rows.filter((r) => r.duplicateOf === row.id).map((r) => r.code)}
              />
            ))}
            {lane.id === "fixed" ? (
              <div className="mt-auto rounded-md border border-dashed border-gray-600 px-3 py-4 text-center text-[13px] leading-snug text-gray-500">
                Drop here and pick the first version with the fix
              </div>
            ) : null}
          </section>
        ))}
        <section aria-label="Close as" className="flex flex-col gap-2.5 rounded-md border border-aisle bg-seat/40 p-3">
          <h2 className="font-mono text-[11px] font-normal tracking-[0.12em] text-gray-300">CLOSE AS</h2>
          {(["wontfix", "duplicate"] as const).map((t) => (
            <div
              key={t}
              {...dropProps(t)}
              className={`flex flex-1 flex-col items-center justify-center gap-1.5 rounded-md border border-dashed p-3.5 text-center text-[13px] leading-snug text-gray-500 ${
                over === t ? "border-beam-500 bg-seat" : "border-gray-600"
              }`}
            >
              <b className="font-semibold text-screen">{t === "wontfix" ? "Won't fix" : "Duplicate"}</b>
              {t === "wontfix" ? "A reason for the user is required" : "The original report is required"}
              <span className="font-mono text-[10px] tracking-wider text-gray-600">
                {t === "wontfix"
                  ? `${rows.filter((r) => r.status === "wontfix" && !r.duplicateOf).length} CLOSED`
                  : `${rows.filter((r) => r.duplicateOf).length} FOLLOWING`}
              </span>
            </div>
          ))}
        </section>
      </div>
      <p className="max-w-[1100px] text-sm leading-relaxed text-gray-400">
        Three working lanes match the three statuses users see. Dropping a card on Fixed asks for the version; dropping it on a
        close-as zone opens a form, and the card does not move until the form is complete. Every card also has a Move menu, so
        nothing needs a mouse. The &ldquo;N SAME&rdquo; count is how many duplicates follow that card.
      </p>

      {/* Closed originals live outside the lanes, with a way back. */}
      {lanes.closed.length > 0 ? (
        <section aria-label="Closed" className="space-y-2">
          <h2 className="font-mono text-[11px] font-normal tracking-[0.12em] text-gray-400">CLOSED &middot; {lanes.closed.length}</h2>
          <div className="grid gap-2.5 md:grid-cols-2 xl:grid-cols-3">
            {lanes.closed.map((row) => (
              <Card
                key={row.id}
                row={row}
                same={same.get(row.id) ?? 0}
                follower={undefined}
                lane="closed"
                disabled={pending}
                onDragStart={() => setDragging(row.code)}
                onDragEnd={() => {
                  setDragging(null);
                  setOver(null);
                }}
                onMove={(t) => requestMove(row.code, t)}
                followers={rows.filter((r) => r.duplicateOf === row.id).map((r) => r.code)}
              />
            ))}
          </div>
        </section>
      ) : null}

      {dialog && active ? (
        <Modal onClose={() => setDialog(null)} label={dialog.kind}>
          {dialog.kind === "fixed" ? (
            <FixedForm
              row={active}
              releases={releases}
              pending={pending}
              onCancel={() => setDialog(null)}
              onSubmit={(v) => run(() => markFixedAction(active.code, v), () => setDialog(null))}
            />
          ) : dialog.kind === "wontfix" ? (
            <WontFixForm
              row={active}
              pending={pending}
              onCancel={() => setDialog(null)}
              onSubmit={(reason) => run(() => closeWontFixAction(active.code, reason), () => setDialog(null))}
            />
          ) : (
            <DuplicateForm
              row={active}
              rows={rows}
              byId={byId}
              pending={pending}
              onCancel={() => setDialog(null)}
              onSubmit={(original, title) =>
                run(() => markDuplicateAction(active.code, original, title), () => setDialog(null))
              }
            />
          )}
          {error ? (
            <p role="alert" className="mt-3 text-sm text-signal">
              {error}
            </p>
          ) : null}
        </Modal>
      ) : null}
    </div>
  );
}

function Card({
  row,
  same,
  follower,
  followers,
  lane,
  disabled,
  onDragStart,
  onDragEnd,
  onMove,
}: {
  row: BugRow;
  same: number;
  follower?: string;
  followers: string[];
  lane: BugLane | "closed";
  disabled: boolean;
  onDragStart: () => void;
  onDragEnd: () => void;
  onMove: (t: MoveTarget) => void;
}) {
  const [menu, setMenu] = useState(false);
  const [open, setOpen] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!menu) return;
    const close = (e: MouseEvent | KeyboardEvent) => {
      if (e instanceof KeyboardEvent && e.key !== "Escape") return;
      if (e instanceof MouseEvent && menuRef.current?.contains(e.target as Node)) return;
      setMenu(false);
    };
    document.addEventListener("mousedown", close);
    document.addEventListener("keydown", close);
    return () => {
      document.removeEventListener("mousedown", close);
      document.removeEventListener("keydown", close);
    };
  }, [menu]);

  const border =
    lane === "looking" ? "border-beam-500" : lane === "fixed" ? "border-cue" : "border-rail";
  // A fixed card can be re-fixed in another version (a release got skipped), so
  // Fixed stays on its menu, worded as the change it is.
  const targets = (Object.keys(MOVE_LABELS) as MoveTarget[]).filter(
    (t) => t === "fixed" || t !== (lane === "closed" ? row.status : lane),
  );

  return (
    <article
      draggable={!disabled}
      onDragStart={(e) => {
        e.dataTransfer.setData("text/plain", row.code);
        e.dataTransfer.effectAllowed = "move";
        onDragStart();
      }}
      onDragEnd={onDragEnd}
      className={`relative flex flex-col gap-1.5 rounded-md border bg-seat p-3 ${border}`}
      data-code={row.code}
      data-lane={lane}
    >
      <div className="flex flex-wrap items-center gap-2">
        <span className="font-mono text-[11px] tracking-[0.08em] text-gray-300">{row.code}</span>
        <span className="rounded-sm border border-gray-600 px-1.5 py-0.5 font-mono text-[10px] tracking-[0.1em] text-gray-300">
          {(row.category ?? "other").toUpperCase()}
        </span>
        {row.status === "fixed" && row.fixedIn ? (
          <span className="whitespace-nowrap rounded-sm border border-cue px-1.5 py-0.5 font-mono text-[10px] tracking-[0.1em] text-cue">
            FIXED FROM {row.fixedIn}
          </span>
        ) : null}
        {row.status === "wontfix" ? (
          <span className="rounded-sm border border-gray-600 px-1.5 py-0.5 font-mono text-[10px] tracking-[0.1em] text-gray-300">
            CLOSED
          </span>
        ) : null}
        <div className="relative ml-auto" ref={menuRef}>
          <button
            type="button"
            aria-label={`Move ${row.code}`}
            aria-haspopup="menu"
            aria-expanded={menu}
            disabled={disabled}
            onClick={() => setMenu((m) => !m)}
            className="h-7 rounded-md border border-transparent px-2 text-xs text-gray-400 hover:border-rail hover:text-screen focus-visible:outline focus-visible:outline-2 focus-visible:outline-beam-500"
          >
            Move
          </button>
          {menu ? (
            <div
              role="menu"
              className="absolute right-0 top-8 z-20 w-44 rounded-md border border-rail bg-seat p-1 shadow-none"
            >
              {targets.map((t) => (
                <button
                  key={t}
                  type="button"
                  role="menuitem"
                  onClick={() => {
                    setMenu(false);
                    onMove(t);
                  }}
                  className="block h-9 w-full rounded-md px-3 text-left text-sm text-gray-200 hover:bg-aisle focus-visible:bg-aisle focus-visible:outline-none"
                >
                  {t === "fixed" && row.status === "fixed" && !row.duplicateOf ? "Change fixed version…" : MOVE_LABELS[t]}
                </button>
              ))}
            </div>
          ) : null}
        </div>
      </div>
      <button
        type="button"
        aria-expanded={open}
        onClick={() => setOpen((o) => !o)}
        className="text-left text-sm font-medium leading-snug text-screen"
      >
        {cardTitle(row)}
      </button>
      <div className="flex flex-wrap gap-x-2 font-mono text-[10px] tracking-[0.06em] text-gray-500">
        {row.appVersion ? <span>{row.appVersion}</span> : null}
        {row.os ? <span>{row.os}</span> : null}
        {same > 0 ? <span className="text-beam-500">{same} SAME</span> : null}
        {follower ? <span className="text-gray-400">FOLLOWS {follower}</span> : null}
      </div>
      {open ? (
        <div className="mt-1 space-y-2 border-t border-aisle pt-2 text-xs leading-relaxed text-gray-300">
          {row.note ? <p className="whitespace-pre-wrap">{row.note}</p> : <p className="text-gray-500">No note.</p>}
          {row.appendix ? (
            <p className="whitespace-pre-wrap border-l-2 border-rail pl-2 text-gray-400">{row.appendix}</p>
          ) : null}
          {row.reason ? (
            <p>
              <span className="font-mono text-[10px] tracking-wider text-gray-500">REASON SENT </span>
              {row.reason}
            </p>
          ) : null}
          <dl className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-0.5 font-mono text-[10px] text-gray-500">
            {row.route ? (
              <>
                <dt>ROUTE</dt>
                <dd className="truncate text-gray-300">{row.route}</dd>
              </>
            ) : null}
            {row.sentryEventId ? (
              <>
                <dt>SENTRY</dt>
                <dd className="truncate text-gray-300">{row.sentryEventId}</dd>
              </>
            ) : null}
            <dt>SENT</dt>
            <dd className="text-gray-300">{new Date(row.createdAt).toLocaleString()}</dd>
            <dt>NOTIFY</dt>
            <dd className="text-gray-300">{row.notifyWhenFixed ? "wants to hear when fixed" : "no"}</dd>
            {followers.length > 0 ? (
              <>
                <dt>SAME</dt>
                <dd className="truncate text-gray-300">{followers.join(", ")}</dd>
              </>
            ) : null}
          </dl>
        </div>
      ) : null}
    </article>
  );
}

function Modal({ children, onClose, label }: { children: React.ReactNode; onClose: () => void; label: string }) {
  const ref = useRef<HTMLDivElement>(null);
  // The latest onClose without re-running the focus effect on every render.
  const closeRef = useRef(onClose);
  useEffect(() => {
    closeRef.current = onClose;
  });
  useEffect(() => {
    ref.current?.querySelector<HTMLElement>("input, textarea, button")?.focus();
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") closeRef.current();
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, []);
  return (
    <div
      className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-booth/80 p-4 pt-[8vh]"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div
        ref={ref}
        role="dialog"
        aria-modal="true"
        aria-label={label}
        className="w-full max-w-[600px] rounded-md border border-rail bg-seat p-6"
      >
        {children}
      </div>
    </div>
  );
}

function Header({ row, title }: { row: BugRow; title: string }) {
  return (
    <div className="mb-4">
      <div className="font-mono text-[11px] tracking-[0.14em] text-gray-500">
        {row.code} &middot; {cardTitle(row, 48).toUpperCase()}
      </div>
      <h3 className="mt-1.5 text-[22px] font-extrabold tracking-tight text-screen">{title}</h3>
    </div>
  );
}

function Preview({ pill, title, body }: { pill: string; title?: string; body: string }) {
  return (
    <div className="space-y-1.5 rounded-md border border-aisle bg-booth p-3" aria-live="polite">
      <div className="font-mono text-[11px] tracking-[0.14em] text-gray-500">WHAT THE USER SEES</div>
      <div className="flex items-center gap-2">
        <span className="rounded-sm border border-gray-600 px-1.5 py-0.5 font-mono text-[10px] tracking-[0.1em] text-gray-300">
          {pill}
        </span>
        {title ? <span className="text-[13px] text-gray-300">{title}</span> : null}
      </div>
      <p className="text-[13px] leading-relaxed text-screen">{body || "Nothing yet."}</p>
    </div>
  );
}

function Actions({
  note,
  onCancel,
  submit,
  disabled,
}: {
  note: string;
  onCancel: () => void;
  submit: string;
  disabled: boolean;
}) {
  return (
    <div className="mt-4 flex items-center justify-between gap-3">
      <span className="text-xs text-gray-500">{note}</span>
      <div className="flex gap-2.5">
        <button type="button" className={btnPlain} onClick={onCancel}>
          Cancel
        </button>
        <button type="submit" className={btnLit} disabled={disabled}>
          {submit}
        </button>
      </div>
    </div>
  );
}

const OTHER = "__other";

function FixedForm({
  row,
  releases,
  pending,
  onCancel,
  onSubmit,
}: {
  row: BugRow;
  releases: { value: string; label: string }[];
  pending: boolean;
  onCancel: () => void;
  onSubmit: (version: string) => void;
}) {
  // A dropdown of the versions we actually ship, with a free-text escape hatch:
  // the fix may land in a build that is not tagged yet, or a skipped one.
  const known = row.fixedIn && releases.some((r) => r.value === row.fixedIn) ? row.fixedIn : null;
  const [choice, setChoice] = useState(known ?? (row.fixedIn ? OTHER : (releases[0]?.value ?? OTHER)));
  const [typed, setTyped] = useState(known ? "" : (row.fixedIn ?? ""));
  const version = choice === OTHER ? normalizeVersion(typed) : choice;
  const bad = fixedFromError(version, row.appVersion);
  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        if (!bad) onSubmit(version);
      }}
    >
      <Header row={row} title="Fixed from which version?" />
      <label className="block text-[13px] text-gray-300" htmlFor="fixed-version">
        The first version that has the fix. Users see &ldquo;Fixed from &hellip; onward&rdquo;, so a skipped build is fine.
      </label>
      <select
        id="fixed-version"
        className={`${inputCls} mt-1.5`}
        value={choice}
        onChange={(e) => setChoice(e.target.value)}
      >
        {releases.map((r) => (
          <option key={r.value} value={r.value}>
            {r.label}
          </option>
        ))}
        <option value={OTHER}>Another version&hellip;</option>
      </select>
      {choice === OTHER ? (
        <input
          aria-label="Version, like 1.4.2"
          className={`${inputCls} mt-2`}
          value={typed}
          onChange={(e) => setTyped(e.target.value)}
          placeholder="1.4.2"
          inputMode="decimal"
          autoFocus
        />
      ) : null}
      <div className="mt-4">
        <Preview
          pill={`FIXED FROM ${version.toUpperCase() || "…"}`}
          title={cardTitle(row, 60)}
          body={`Fixed from ${version || "…"} onward. Thank you for flagging it, update when you can.`}
        />
      </div>
      <Actions
        note={bad ?? "Followers are fixed with it."}
        onCancel={onCancel}
        submit="Mark fixed"
        disabled={pending || !!bad}
      />
    </form>
  );
}

function WontFixForm({
  row,
  pending,
  onCancel,
  onSubmit,
}: {
  row: BugRow;
  pending: boolean;
  onCancel: () => void;
  onSubmit: (reason: string) => void;
}) {
  const [reason, setReason] = useState("");
  const bad = reasonError(reason);
  const n = nonSpaceLength(reason);
  const prev = wontFixPreview(row, reason);
  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        if (!bad) onSubmit(reason.trim());
      }}
    >
      <Header row={row} title="Close without a fix" />
      <label className="block text-[13px] text-gray-300" htmlFor="wontfix-reason">
        Tell the user why. They will read this exactly as written.
      </label>
      <textarea
        id="wontfix-reason"
        className={`${inputCls} mt-1.5 h-24 resize-y leading-relaxed`}
        value={reason}
        onChange={(e) => setReason(e.target.value)}
        aria-invalid={!!bad}
        aria-describedby="wontfix-count"
      />
      <div className="mt-2 flex flex-wrap gap-2">
        {STARTER_LABELS.map((label, i) => (
          <button
            key={label}
            type="button"
            className={chipCls}
            onClick={() => setReason((r) => (r.trim() ? `${r.trim()} ${REASON_STARTERS[i]}` : REASON_STARTERS[i]))}
          >
            {label}
          </button>
        ))}
      </div>
      <div className="mt-4">
        <Preview pill={prev.pill} title={prev.title} body={prev.body} />
      </div>
      <p id="wontfix-count" className="sr-only">
        {n} of {MIN_REASON_CHARS} characters
      </p>
      <Actions
        note={n < MIN_REASON_CHARS ? `Minimum ${MIN_REASON_CHARS} characters (${n} so far)` : "Ready to send"}
        onCancel={onCancel}
        submit="Close with this reason"
        disabled={pending || !!bad}
      />
    </form>
  );
}

function DuplicateForm({
  row,
  rows,
  byId,
  pending,
  onCancel,
  onSubmit,
}: {
  row: BugRow;
  rows: BugRow[];
  byId: Map<string, BugRow>;
  pending: boolean;
  onCancel: () => void;
  onSubmit: (originalCode: string, publicTitle?: string) => void;
}) {
  const [query, setQuery] = useState("");
  const [pickedId, setPickedId] = useState<string | null>(null);
  const [title, setTitle] = useState("");
  const results = useMemo(() => searchOriginals(row, rows, query), [row, rows, query]);
  const picked = pickedId ? byId.get(pickedId) : undefined;
  const check = checkOriginal(row, picked, byId);
  const root = check.ok ? check.root : undefined;
  const needsTitle = !!root && !root.publicTitle;
  const prev = root ? duplicatePreview(root) : null;
  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        if (root) onSubmit(root.code, needsTitle ? title : undefined);
      }}
    >
      <Header row={row} title="Same as an existing report" />
      <label className="block text-[13px] text-gray-300" htmlFor="dup-search">
        Pick the original. The user will follow it.
      </label>
      <input
        id="dup-search"
        className={`${inputCls} mt-1.5`}
        placeholder="Search by code or words: chat cellular"
        value={query}
        onChange={(e) => setQuery(e.target.value)}
      />
      <ul className="mt-2 space-y-1.5" aria-label="Possible originals">
        {results.map((r) => {
          const on = pickedId === r.id;
          return (
            <li key={r.id}>
              <button
                type="button"
                aria-pressed={on}
                onClick={() => setPickedId(r.id)}
                className={`flex w-full flex-col gap-1 rounded-md border p-2.5 text-left ${
                  on ? "border-beam-500 bg-beam-500/10" : "border-rail bg-seat hover:border-gray-500"
                }`}
              >
                <span className="flex items-center gap-2">
                  <span className="font-mono text-[11px] tracking-[0.08em] text-gray-300">{r.code}</span>
                  <span className="rounded-sm border border-gray-600 px-1.5 py-0.5 font-mono text-[10px] tracking-[0.1em] text-gray-300">
                    {r.status === "looking" ? "LOOKING INTO IT" : r.status === "fixed" ? "FIXED" : r.status === "wontfix" ? "CLOSED" : "RECEIVED"}
                  </span>
                </span>
                <span className="text-sm text-screen">{cardTitle(r, 70)}</span>
              </button>
            </li>
          );
        })}
        {results.length === 0 ? <li className="text-[13px] text-gray-500">Nothing matches yet.</li> : null}
      </ul>
      {check.ok === false && picked ? <p className="mt-2 text-sm text-signal">{check.error}</p> : null}
      {check.ok && check.viaFollower ? (
        <p className="mt-2 text-xs text-gray-400">
          {picked?.code} is itself a duplicate, so this will follow its original, {check.root.code}.
        </p>
      ) : null}
      {needsTitle && root ? (
        <div className="mt-3">
          <label className="block text-[13px] text-gray-300" htmlFor="dup-title">
            A neutral title users will see for {root.code} (optional, never its reporter&apos;s note)
          </label>
          <input
            id="dup-title"
            className={`${inputCls} mt-1.5`}
            placeholder={publicTitleOf(root)}
            value={title}
            maxLength={120}
            onChange={(e) => setTitle(e.target.value)}
          />
        </div>
      ) : null}
      <div className="mt-4">
        <Preview pill={prev?.pill ?? "SAME AS …"} body={prev?.body ?? "Pick the original to see what the user will read."} />
      </div>
      <Actions
        note="Duplicates of a duplicate resolve to the root"
        onCancel={onCancel}
        submit="Mark as duplicate"
        disabled={pending || !root}
      />
    </form>
  );
}
