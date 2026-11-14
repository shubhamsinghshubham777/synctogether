"use client";

import { useTransition } from "react";
import { useState } from "react";
import { grantRewardAction, markAddedAction, type RewardSummary } from "./actions";

const btn =
  "px-3 py-1.5 rounded-md bg-aisle hover:bg-aisle/80 text-xs font-mono text-gray-300 hover:text-white border border-rail transition-colors cursor-pointer disabled:opacity-50";

/** Mark one tester, or every pending one, as added to the Play Console list. */
export function AddedButton({ id, all }: { id?: number; all?: boolean }) {
  const [pending, start] = useTransition();
  return (
    <button
      type="button"
      disabled={pending}
      className={btn}
      onClick={() => start(() => markAddedAction(all ? undefined : [id as number]))}
    >
      {pending ? "Saving…" : all ? "Mark all as added" : "Mark added"}
    </button>
  );
}

/** Grant the 2-week Premium thank-you to one tester, or to every added one, and say what happened. */
export function RewardButton({ id, all }: { id?: number; all?: boolean }) {
  const [pending, start] = useTransition();
  const [note, setNote] = useState<string | null>(null);
  const say = (r: RewardSummary) =>
    setNote(
      [
        r.granted && `${r.granted} granted`,
        r.no_account && `${r.no_account} have no account yet`,
        r.has_plan && `${r.has_plan} already have a plan`,
      ]
        .filter(Boolean)
        .join(" · ") || "nothing to grant",
    );
  return (
    <span className="inline-flex items-center gap-2">
      <button
        type="button"
        disabled={pending}
        className={btn}
        onClick={() =>
          start(async () => {
            try {
              say(await grantRewardAction(all ? undefined : [id as number]));
            } catch (e) {
              setNote(e instanceof Error ? e.message : "failed");
            }
          })
        }
      >
        {pending ? "Granting…" : all ? "Grant 14 days to all added" : "Grant 14 days"}
      </button>
      {note && <span className="text-xs font-mono text-gray-400">{note}</span>}
    </span>
  );
}
