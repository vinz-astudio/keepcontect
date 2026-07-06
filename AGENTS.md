# AGENTS.md — Keep Contact

This project is governed by a shared **Obsidian "2nd Brain"** — the single source of truth for
the human **and every IDE agent (Codex, Antigravity, Claude Code, …)**. Read it before coding,
and write changes back into it.

**Brain location** (relative to this repo root): `../../Obsidian Brain/2nd Brain/`
(absolute on this machine: `C:\Users\vizen\Desktop\Obsidian Brain\2nd Brain\`)

## Read first (in order)
1. `Brain Rules.md` — vault structure & rules (mandatory).
2. `Projects/Keep Contact/Keep Contact.md` — project home + 5 core IDE/AI principles.
3. `Coordination/Coordination.md` + `Coordination/Active Work.md` — multi-IDE protocol + live board.
4. `Projects/Keep Contact/Decisions.md` — binding decisions (ADR). `accepted` ones are non-negotiable.
5. The relevant `Projects/Keep Contact/**` business-logic notes for whatever you're touching.

## Multi-IDE coordination protocol
- **Sign every coordination note** `[<IDE> · YYYY-MM-DD HH:mm]`; append/edit only your own lines.
- **Big or irreversible changes** (architecture, DB schema, cross-module, migrations): write a
  proposal in `Active Work.md` → wait for the human to record it as an `accepted` ADR in
  `Decisions.md` → then execute. **Small fixes** (bugfix, copy, local refactor): just do it + log.
- **After a change**: update the truth notes in `Projects/Keep Contact/`, append an
  `Experiences/Keep Contact/Dev Log.md` entry (the *why*), and clear/update the `Active Work.md` item.
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

> The Brain path above is machine-relative (works while both folders sit under `Desktop/`). If your
> IDE runs elsewhere, adjust the path or ask the human for the vault location.
