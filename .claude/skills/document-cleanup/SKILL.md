---
name: document-cleanup
description: >-
  Audit SyncTogether's documentation against the actual code, fix anything outdated or inaccurate, and delete docs that no longer earn their place. Covers docs/*.md (especially docs/self-hosting.md), README.md, AGENTS.md, website/README.md, the .env.example files and .agents/rules. Use when the user says "check the docs", "docs are outdated", "clean up documentation", "update the self-hosting guide", "delete unnecessary docs", or "/document-cleanup". Optional arg narrows the scope (e.g. "/document-cleanup self-hosting").
---

# Document cleanup

Docs rot silently: code changes, the doc keeps describing the old shape, and nothing fails. This skill checks every factual claim against the source of truth and fixes or deletes what doesn't hold up.

**The code is the source of truth, never another doc.** `CLAUDE.md` is usually current, but verify a claim in the code before copying it from `CLAUDE.md` into another doc.

## 1. Inventory

```bash
ls docs/ .agents/rules/ .agents/skills/ .claude/skills/
wc -l docs/*.md README.md AGENTS.md website/README.md
ls supabase/functions supabase/migrations scripts
```

For each doc, find what points at it. A doc that nothing references is a candidate for deletion:

```bash
grep -rln "<doc-basename>" --exclude-dir=node_modules --exclude-dir=build --exclude-dir=.git .
```

## 2. Verify claims against the code

Check each concrete claim: commands, paths, ports, env var names, defaults, versions, file lists and feature descriptions. These are the places that have drifted before:

| Claim in docs | Source of truth |
|---|---|
| Flutter version | `.fvmrc` |
| Client `--dart-define` keys and defaults | `lib/env.dart`, plus `bool.fromEnvironment` in `lib/` |
| Edge Functions list | `ls supabase/functions` |
| Edge Function secrets | `grep -rhoE "Deno\.env\.get\(['\"][A-Z0-9_]+" supabase/functions`, compared with `supabase/functions/.env.example` |
| Auth config (captcha, providers, manual linking, redirect URLs, site_url) | `supabase/config.toml`, `supabase/.env.example` |
| Website env vars | `grep -rhoE "process\.env\.[A-Z_]+" website/app website/lib website/components`, compared with `website/.env.example` and `website/README.md` |
| LiveKit self-host config | `docker-compose.selfhost.yml`, `docker/livekit.yaml` |
| Things that ship switched off (for example `app_settings.r2_cleanup.endpoint_url`) | the seeding migration |
| Tier limits and feature toggles | seeds in `supabase/migrations/*`, compared with `docs/feature-toggles.md` |
| Hardcoded production URLs (`synctogether.app`) | `grep -rn "synctogether.app" lib` - self-hosters must be told about any that aren't configurable |
| Scripts and their subcommands | `scripts/*.sh` headers |
| Supabase CLI commands | real CLI subcommands only (for example, there is no `supabase functions logs`) |
| Links | every relative link must resolve from the doc's own directory; no `file:///` links |

For each self-hosting step, ask: **would a fresh self-hoster following this succeed?** Look especially for:
- steps a default config makes mandatory but the doc calls optional
- config that `db push` doesn't apply (auth config needs `supabase config push`)
- secrets that must be set before a deploy
- features that ship inert until an operator configures them
- TLS or reverse-proxy requirements

## 3. Fix

- Edit in place and keep each doc's existing structure and tone. Fix what's wrong; don't rewrite what's right.
- No LaTeX. Use plain markdown tables and operators.
- If a doc describes work as "planned" or "not started" that has since shipped, and its content now lives in `CLAUDE.md` or the code, delete it.
- Keep `.env.example` files in step with the code. They are documentation too.

## 4. Delete unnecessary docs

Delete a doc (`git rm`) only when **all** of these hold:
- Nothing references it: not code, tools, migrations, `CLAUDE.md`, `AGENTS.md` or README.
- Its content is obsolete or duplicated elsewhere.
- It isn't operator reference material (`feature-toggles.md`, `self-hosting.md`, `known-issues.md` stay).

Something referenced as a source of truth stays, even if it reads like an old plan. For example, `docs/gamification-plan.md` holds the badge-art prompts that `tool/process_badge_art.py` depends on. After deleting, fix any links and indexes that listed the file.

## 5. Finish

- Re-grep for links to anything deleted or renamed.
- If only docs changed, don't run the Flutter checks.
- **Don't commit.** The user commits themselves.
- Report per file what was wrong and what changed, list what was deleted and why, and say what was checked but left alone.
