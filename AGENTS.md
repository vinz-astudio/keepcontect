# AGENTS.md — Keep Contact

This project is governed by a shared **Obsidian "2nd Brain"** — the single source of truth for
the human **and every IDE agent (Codex, Antigravity, Claude Code, …)**. Read it before coding,
and write changes back into it.

**Brain location** (relative to this repo root): `../../Obsidian Brain/2nd Brain/`
(absolute on this machine: `C:\Users\vizen\Desktop\Obsidian Brain\2nd Brain\`)

## Read first
The session-start hook (`Coordination/tools/context-inject.mjs`) loads this project's Invariants & Map,
Lessons and Memory, the human's preferences, and a "开工提醒" block when something waits on the human.
Do not re-read them. If no "Brain context" block is present (an agent without the hook), read
`Projects/Keep Contact/Keep Contact Invariants & Map.md` first; it links the lessons page.

Then read only what the task touches:
1. `Projects/Keep Contact/Decisions.md` — binding decisions (ADR). `accepted` ones are non-negotiable.
   It is about 114 KB: search it for the area you change, do not load it whole.
2. The relevant `Projects/Keep Contact/**` business-logic notes.
3. `Coordination/Active Work.md` — only for coordination work.

## Multi-IDE coordination protocol
- **Sign every coordination note** `[<IDE> · YYYY-MM-DD HH:mm]`; append/edit only your own lines.
- **Big or irreversible changes** (architecture, DB schema, cross-module, migrations): write a
  proposal in `Active Work.md` → wait for the human to record it as an `accepted` ADR in
  `Decisions.md` → then execute. **Small fixes** (bugfix, copy, local refactor): just do it + log.
- **After a change**: write back to the Brain only on an event: changed project truth (update the notes in
  `Projects/Keep Contact/`), an accepted decision (one line under "快记" in `Decisions.md`; an ADR if it is
  big or irreversible), a handoff, a blocker, or release state (an `Experiences/Keep Contact/Dev Log.md`
  entry with the *why*). Ordinary completion needs no Dev Log entry.
- The human is the arbiter & sync point. **Code/migrations are the runtime truth; keep the Brain aligned to them.**
- **Token economy**: agent-to-agent notes (`Active Work`, Threads) and your own working scratch use terse "caveman" style — drop grammar/filler/pleasantries, shortest tokens, any language. Only human-facing decision summaries stay in plain readable prose.

## Roles
Human = decision brain & final arbiter. Brain (Obsidian) = memory brain / source of truth. IDE agents (you) = hands & feet. Ollama = assistant between agents and the Brain (retrieval + mechanical glue) — never the arbiter or lead reasoner.

## Repo facts (don't relearn the hard way)
- Stack: React + Vite + TypeScript PWA · Supabase (Postgres) · Capacitor (Android) · Tauri (desktop).
- DB: add **new** migration files only, never edit old ones (`supabase/migrations/`); apply via Supabase MCP/CLI.
- Releasing: `npm run release:android -- <ver>` bumps 3 of 4 version files + builds the APK; the Tauri
  desktop build and `tauri.conf.json` are **separate/manual** — all four version files must move together.
- Secrets and the Android keystore are gitignored — never commit them.
- **Android notifications, background work or permissions: read `android/PLAY-CONSTRAINTS.md` first.**
  The APK and the AAB are one codebase and KC is going to Play, so "works on a test phone" is not the
  bar — "passes review and behaves the same" is. Several Play capabilities degrade *silently* when not
  granted, which is how a feature can look shipped and be dead.

> The Brain path above is machine-relative (works while both folders sit under `Desktop/`). If your
> IDE runs elsewhere, adjust the path or ask the human for the vault location.
