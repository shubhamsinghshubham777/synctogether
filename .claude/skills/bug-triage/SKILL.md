---
name: bug-triage
description: >-
  Work the SyncTogether bug board: read user bug reports, find duplicates, mark the ones being worked as LOOKING INTO IT, fix them in the code and commit with a Fixes-Bug trailer so the release skill can mark them fixed once every store has the build. Use when the user says "triage bugs", "fix reported bugs", "work the bug board", "look at the bug reports", "fix BUG-XXXX", or "/bug-triage". Optional arg: a ticket code (e.g. "/bug-triage BUG-7K2M") to work one report.
---

# Bug triage

Users send reports from the in-app bug button. Each one is a row on the bug board
(`bug_reports`, the internal page at `/internal/bugs`) and the user sees its
status in "Your reports". This skill works that board from the terminal with
`scripts/bugs.ts`. Read `docs/agent/feedback.md` first if you have not touched
the feedback system before.

What you set is read by the person who reported it. That is why the rules below
are strict about who may move a ticket where.

## Who changes what

| Change | Who | How |
|---|---|---|
| received -> **LOOKING INTO IT** | **You, on your own**, the moment you start work on a ticket | `node scripts/bugs.ts looking BUG-XXXX` |
| -> **FIXED** (from a version) | **Never you.** The release skill does it, and only after every store has accepted the build | `/release` step 8, or `/release close-bugs X.Y.Z` |
| -> **WON'T FIX** | The user (the human you work for), with a reason text they approved | `wontfix ... --confirm` only after approval |
| -> **DUPLICATE** of another ticket | The user, after you propose it | `duplicate ... --confirm` only after approval |
| LOOKING -> back to received, or any reopen | The user | `reopen ... --confirm` only after approval |

Do not mark anything fixed "because the code is merged". A fix is only real for
users once a build with it is on their store, and users are told "fixed from
X.Y.Z onward".

## Workflow

1. **See the board.** Every command below defaults to the board named in the
   environment (production) and prints `Target: ...` before any write. Add
   `--local` when practising against the local stack.

   ```bash
   node scripts/bugs.ts list open          # received + looking, with same-counts
   ```

   The "N same" count is how many other reports are the same issue. Work the
   tickets with the highest counts, and the ones on the newest app version,
   first, unless the user names one.

2. **Read the ticket.**

   ```bash
   node scripts/bugs.ts show BUG-XXXX      # note, app version, context, sentry id, followers
   ```

   The context holds the app version, the screen route, sync, media and AV
   state, and the last trace events. The Sentry event id, when present, links
   the screenshot and the breadcrumb trail.

3. **Check for duplicates before you start.**

   ```bash
   node scripts/bugs.ts find "words from the note"
   ```

   If the report looks like one already on the board, **tell the user and
   propose closing it as a duplicate** of the older one (give both codes and one
   line on why they match). Do not apply it yourself. Twelve identical reports
   should become one piece of work.

4. **Start the work, then say so.** When you begin on a ticket:

   ```bash
   node scripts/bugs.ts looking BUG-XXXX [BUG-YYYY ...]
   ```

   It is safe to repeat. It refuses a ticket that is already fixed, won't-fixed
   or a duplicate (use `reopen`, with the user's say-so). Users see "Looking
   into it" immediately, so only run it for tickets you are really picking up
   now, not for the whole list.

5. **Reproduce and fix** following `CLAUDE.md`: read the matching
   `docs/agent/*.md` for the area first, instrument as you go, tests for the
   fix, motion/design rules for UI, verify every UI change in a browser. A
   report you cannot reproduce is not a won't-fix: say what you tried, keep it
   LOOKING, and ask the user.

6. **Commit with the trailer.** One `Fixes-Bug:` line per ticket, in the commit
   message body, in the standard git trailer position (last paragraph):

   ```
   fix(sync): the seek bar no longer drifts after two quick pauses

   The pause handler restarted the settle window without clearing the old one.

   Fixes-Bug: BUG-7K2M
   Fixes-Bug: BUG-3F9A
   ```

   The release skill reads exactly these lines, so a typo means a ticket is not
   closed. A commit that only helps (a partial fix) does **not** carry the
   trailer. Follow the usual rules: format, analyze and test before committing,
   no `Co-Authored-By` or "Generated with" lines, commit on `main`.

7. **Tell the user what changed on the board**, every time: which tickets you
   moved to LOOKING INTO IT, which commits carry which `Fixes-Bug`, which
   tickets you think are duplicates or won't-fix (with your suggested reason),
   and that nothing is marked FIXED until the release.

## Closing without a fix: won't fix and duplicate

Both are shown to the person who reported it, so they need a human decision.

- **Won't fix** needs a reason the user will read **verbatim** under a calm
  "Closed" tag. Draft it, show it to the user, and run the command with
  `--confirm` only after they approve the exact text.

  ```bash
  node scripts/bugs.ts wontfix BUG-XXXX --reason="..."            # prints the plan, changes nothing
  node scripts/bugs.ts wontfix BUG-XXXX --reason="..." --confirm  # after approval
  ```

  Write it as: why it behaves that way (or why we cannot do it), what we did
  about it if anything, and what they can do next. Calm, specific, no blame, no
  corporate apology, no jargon, and **never the word "rejected"**. At least 20
  characters. Example: "This is how the fold works on purpose: the seek bar
  steps aside so it never sits on the hinge, which can look like a jump. We've
  added a line about it to the FAQ so the next person knows."

- **Duplicate** links the ticket to its original. The user then follows the
  original's live status (its code, a neutral title and its status, never the
  other person's note). When the original is fixed or closed, every duplicate
  follows. Always point at the oldest or best-described report.

  ```bash
  node scripts/bugs.ts duplicate BUG-XXXX --of=BUG-YYYY            # plan
  node scripts/bugs.ts duplicate BUG-XXXX --of=BUG-YYYY --confirm  # after the user agrees
  ```

## Data handling

Reports are user data: notes, contexts, account ids and screenshots.

- Use them to reproduce and fix. **Do not paste a note, a screenshot, a context
  blob or an account id into a commit message, an issue, a PR, a log line or a
  test fixture.** Describe the cause in your own words ("the pause handler...").
- A test for a report uses made-up data, never the reporter's.
- Never put chat text or file paths from a report anywhere that is committed.
- The board is the only place a ticket's content lives; the commit trailer holds
  just the code (`BUG-XXXX`), which carries no personal data.

## Practising

`--local` runs the same commands against the local Supabase stack
(`./scripts/dev.sh`), where you can create throwaway rows. The pure logic is
tested by `node --test scripts/tests/bugs_logic.test.ts`.
