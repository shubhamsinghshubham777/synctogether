---
name: supabase-drift
description: >-
  Compare the local Supabase stack (migrations in supabase/migrations + the running
  local Postgres container) against the live/linked Supabase project using the
  supabase MCP tools, report exactly what has drifted (missing/extra migrations,
  schema differences, extension/config divergence), and - only after the user
  explicitly confirms - resolve it by applying the missing migrations to whichever
  side is behind. Use when the user asks to "check for Supabase drift", "compare
  local and live Supabase", "has the database drifted", "sync local and prod
  schema", or "/supabase-drift".
---

# Supabase local vs. live drift check

Read-only diagnosis first, destructive action only on explicit confirmation.
Never apply anything to the live project without the user saying yes to the
specific statements that will run.

## 1. Gather local state

- `supabase/migrations/*.sql` filenames, sorted - this is the local migration
  history, source of truth for what *should* exist everywhere.
- `supabase migration list` (CLI) if the local stack is running, to see which
  migrations the local Postgres container has actually applied versus what's on
  disk - these can disagree if someone edited a migration file after it ran
  locally without resetting.
- If the local stack isn't running, note that and skip the "applied locally"
  check rather than starting it unasked (see `[[local-backend-startup]]` memory
  - starting Docker/`./scripts/dev.sh` needs the user's go-ahead unless they
    already asked for the full check including local state).

## 2. Gather live state via the supabase MCP tools

- `mcp__supabase__list_migrations` - the live project's applied migration
  version/name history.
- `mcp__supabase__list_tables`, `mcp__supabase__list_extensions` for a schema
  snapshot if a deeper structural diff is needed (not just migration-history
  diff).
- `mcp__supabase__get_advisors` (security + performance) is a useful bonus
  signal while already looking at the live project, but is a separate report -
  don't conflate advisory lint with drift.

## 3. Diff and report

Compare the three lists (on-disk files, local-applied, live-applied) and report
plainly:

- **Migrations present locally (on disk) but not applied on live** - the common
  case after `git pull`ing someone else's migration before running
  `supabase db push`.
- **Migrations applied on live but missing from `supabase/migrations/` on disk**
  - someone ran a one-off change directly against the live project, or a
    migration file was deleted/renamed after being pushed. This is the
    dangerous direction: there is no local file to replay, so resolving it
    means either writing a new migration that captures the live state, or
    accepting live is ahead and pulling its schema down.
- **Migrations applied locally but not on disk** - a locally-run migration
  whose file was edited or removed after the fact; local Postgres and the repo
  disagree even before live enters the picture.
- Order-of-application mismatches (same filenames, different applied order) if
  any show up.

Present this as a short table/list: filename/version, on disk?, applied
locally?, applied live?. State the resolution direction for the common case
(push local migrations up) plainly, and flag the dangerous case (live has
something local doesn't) as needing a decision, not just a push.

## 4. Resolve only on confirmation

Ask explicitly before doing anything to the live project - e.g. via
AskUserQuestion with options like "Push missing migrations to live", "Show me
the SQL first", "Don't touch live, just tell me". Never assume "yes, fix it"
from "check for drift".

- **Local ahead (the common, safe case)**: apply the missing migration(s) to
  live in order, one at a time, via `mcp__supabase__apply_migration` (preferred
  over raw `execute_sql` for anything that should leave a migration-history
  row) - or tell the user to run `supabase db push` themselves if they'd rather
  drive it. Re-run `mcp__supabase__list_migrations` after to confirm it landed.
- **Live ahead or diverged (someone changed live directly)**: do not silently
  "fix" this by overwriting live. Show the user what's live-only, and offer to
  either (a) write a new local migration file that captures the live-only
  change so the repo catches up, or (b) if the live change was a mistake,
  draft a migration that reverts it - either way, the user picks which
  direction is correct before anything is written or applied.
- Never run `supabase db reset` or any destructive statement against live as
  part of "resolving" drift.

## Notes

- This project's local debug builds point at the local stack by design (see
  CLAUDE.md's "Debug builds point at the local Supabase stack" note) - that's
  what makes this check safe to run routinely without any risk to the live
  project from the app itself; the risk here is purely in step 4's writes.
- A linked project's ref (for `mcp__supabase__*` calls that need one) comes
  from `supabase/.temp/project-ref` or `supabase status`/`supabase link` state
  if more than one project could be meant - ask the user which project if it's
  ambiguous rather than guessing.
