# Migration Replay Compatibility Harness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a reproducible local/CI-only Supabase migration replay lane that preserves every historical repository migration while explicitly adapting the hash-pinned legacy defects authorized by ADR-0024 and its 2026-07-26 BOM amendment.

**Architecture:** A pure Node.js core validates source location and SHA-256 hashes, constructs an ignored disposable Supabase project under `supabase/.temp/replay-compat/project`, inserts one synthetic pre-migration auth fixture, and corrects exactly one known token only in the temporary copy. A thin CLI invokes the pinned official Supabase CLI with `--local` and the disposable workdir, then runs pgTAP; it exposes no linked, remote, database-URL, push, repair, or history-marking option.

**Tech Stack:** Node.js 22 built-ins (`node:crypto`, `node:fs/promises`, `node:path`, `node:child_process`), Vitest 3, Supabase CLI 2.109.1, local PostgreSQL 17 through Podman.

**Local candidate status (2026-07-26):** Steps 1–7 are complete. The focused harness suite passes 12/12; a fresh disposable replay applies every migration through ADR-0027 and passes both pgTAP files, 66/66. Step 8 remains intentionally open until the independent harness audit and coordinated commit are complete. No production or linked Supabase action is part of this plan.

## Global Constraints

- ADR-0024 is binding: repository migration files remain byte-for-byte unchanged.
- The only accepted source hashes are:
  - `supabase/migrations/20260625174615_sync_activity_truth.sql` → `0c92784730710fe1b487c01f8199115f1fc7053238e4607c52428e2cb45a2090`
  - `supabase/migrations/20260626072619_scoped_group_activity_views.sql` → `bca5cd87009bba29e5906487322af56ca99c30db1d9717113886f347dbec85ff`
  - `supabase/migrations/20260623090000_gm_admin_console.sql` → `cf9f5912586c08fe7368d51c1cd7a4fb4aef53723298d7a4a92500f71837c271`
  - `supabase/migrations/20260624140000_adaptive_routine_impl.sql` → `55572dac4d31de589ee7e91a04b2e74ce822c2784beb53389c5b295382956e84`
- The disposable project root is exactly `supabase/.temp/replay-compat/project`.
- The synthetic compatibility migration is exactly `20260623085959_local_replay_admin_fixture.sql`, ordered immediately before `20260623090000`.
- The temporary adaptive migration copy must contain exactly one replacement: literal `</loop>` → `end loop;`.
- The 2026-07-26 ADR-0024 amendment authorizes only the two named BOM corrections above: each source must have exactly one leading `EF BB BF` byte sequence, and its temporary copy must equal `source.subarray(3)` byte-for-byte. Missing, non-leading, repeated, unexpected, or additional repository BOMs fail closed.
- Source hashes cover all four authorized files and must be verified before and after preparation. The copied tree must match source byte-for-byte except for the synthetic fixture, the one authorized `</loop>` correction, and the two authorized BOM removals. The manifest records every compatibility action and its resulting hash.
- Disposable containment is resolved against filesystem reality: symlink/junction traversal outside `supabase/.temp` fails closed even where lexical path containment appears valid.
- Every mismatch in root containment, source hash, expected token count, source-copy equality, or child-process exit status fails closed.
- Runtime commands must include `--local --workdir <disposable-project-root>` and must never include `--linked`, `--db-url`, `db push`, `migration repair`, or `migration up`.
- The synthetic auth identity is fixed test-only data: UUID `b897a59f-0a54-42df-9926-8452e477d8bd`, email `gm-baseline@example.invalid`, `aud='authenticated'`, `role='authenticated'`.
- No network/API billing, production connection, deploy, release, cron scheduling, live alert change, or old-migration edit is authorized.

---

### Task 1: Hash-Pinned Disposable Replay Harness

**Files:**
- Create: `scripts/local-supabase-replay-core.mjs`
- Create: `scripts/local-supabase-replay.mjs`
- Create: `scripts/local-supabase-replay.test.mjs`
- Modify: `package.json`
- Runtime-only: `supabase/.temp/replay-compat/project/**`

**Interfaces:**
- Produces: `prepareReplayProject({ repoRoot, disposableProjectRoot? }): Promise<ReplayManifest>`
- Produces: `adaptLegacyRoutineSql(sourceText): { sql: string, replacementCount: 1 }`
- Produces: `buildReplayCommands(disposableProjectRoot): ReadonlyArray<{ command: string, args: string[] }>`
- Produces: `runReplay({ repoRoot, env?, spawnImpl? }): Promise<ReplayManifest>`
- `ReplayManifest` is a plain object with `disposableProjectRoot`, `verifiedInputs`, `fixtureMigration`, `patchedMigration`, and `replacementCount`.
- `package.json` exposes `"db:replay:compat": "node scripts/local-supabase-replay.mjs"`.

- [x] **Step 1: Write failing behavioral tests**

Create `scripts/local-supabase-replay.test.mjs` using real temporary directories and real filesystem effects. Before the hash-drift test, copy the repository `supabase/config.toml`, `supabase/tests`, and `supabase/migrations` into a temporary fake repository; remove only the test-owned OS temporary directory afterward.

Required test cases:

```js
it('prepares a disposable project without changing either source migration', async () => {
  const beforeAdmin = await readFile(ADMIN_SOURCE);
  const beforeAdaptive = await readFile(ADAPTIVE_SOURCE);
  const manifest = await prepareReplayProject({ repoRoot: REAL_REPO_ROOT });

  expect(manifest.replacementCount).toBe(1);
  expect(await readFile(ADMIN_SOURCE)).toEqual(beforeAdmin);
  expect(await readFile(ADAPTIVE_SOURCE)).toEqual(beforeAdaptive);
  expect(await readFile(manifest.patchedMigration, 'utf8')).not.toContain('</loop>');
  expect(await readFile(manifest.patchedMigration, 'utf8')).toContain('end loop;');
  expect(await readFile(manifest.fixtureMigration, 'utf8')).toContain(
    'b897a59f-0a54-42df-9926-8452e477d8bd',
  );
});

it('fails before replay when a pinned source hash changes', async () => {
  const fakeRepo = await copyReplayInputsToTemp();
  await appendFile(
    join(fakeRepo, 'supabase/migrations/20260623090000_gm_admin_console.sql'),
    '\n-- drift\n',
  );

  await expect(prepareReplayProject({ repoRoot: fakeRepo }))
    .rejects.toThrow(/hash mismatch.*20260623090000/i);
});

it('fails when the authorized token is missing or repeated', () => {
  expect(() => adaptLegacyRoutineSql('begin\\nend loop;'))
    .toThrow(/expected exactly one <\/loop> token/i);
  expect(() => adaptLegacyRoutineSql('begin\\n</loop>\\n</loop>'))
    .toThrow(/expected exactly one <\/loop> token/i);
});

it('rejects a disposable output outside supabase/.temp', async () => {
  await expect(prepareReplayProject({
    repoRoot: REAL_REPO_ROOT,
    disposableProjectRoot: join(REAL_REPO_ROOT, 'outside-replay'),
  })).rejects.toThrow(/must stay inside supabase[\\/]\.temp/i);
});

it('builds only pinned local reset and pgTAP commands', () => {
  const commands = buildReplayCommands(DISPOSABLE_PROJECT_ROOT);
  expect(commands).toEqual([
    {
      command: process.platform === 'win32' ? 'npm.cmd' : 'npm',
      args: [
        'exec', '--yes', '--package=supabase@2.109.1', '--',
        'supabase', 'db', 'reset', '--local',
        '--workdir', DISPOSABLE_PROJECT_ROOT, '--no-seed',
      ],
    },
    {
      command: process.platform === 'win32' ? 'npm.cmd' : 'npm',
      args: [
        'exec', '--yes', '--package=supabase@2.109.1', '--',
        'supabase', 'test', 'db', '--local',
        '--workdir', DISPOSABLE_PROJECT_ROOT,
      ],
    },
  ]);
  expect(JSON.stringify(commands)).not.toMatch(
    /--linked|--db-url|db push|migration repair|migration up/i,
  );
});

it('stops after the first failed local command', async () => {
  const calls = [];
  const spawnImpl = async (command, args) => {
    calls.push([command, args]);
    return { exitCode: 23 };
  };

  await expect(runReplay({ repoRoot: REAL_REPO_ROOT, spawnImpl }))
    .rejects.toThrow(/local replay command failed.*23/i);
  expect(calls).toHaveLength(1);
});
```

The production mutations caught by these tests are: accepting an unreviewed historical file, patching the repository instead of a disposable copy, applying zero/multiple token replacements, writing outside the ignored boundary, adding a remote-capable CLI flag, or continuing after a failed reset.

**2026-07-26 ADR-0024 amendment requirements:** Extend behavioral tests before implementation to prove the two exact hash-pinned BOM migrations are copied with one and only one leading `EF BB BF` stripped; the output bytes are precisely `source.subarray(3)`; and missing, non-leading, doubled, drifted, unexpected, or additional repository BOMs, plus a symlink/junction escape, fail closed. The manifest must include every compatibility action and resulting hash.

- [x] **Step 2: Run the focused test and verify RED**

Run:

```powershell
npm test -- scripts/local-supabase-replay.test.mjs
```

Expected: FAIL because `scripts/local-supabase-replay-core.mjs` does not exist.

- [x] **Step 3: Implement the pure core**

Create `scripts/local-supabase-replay-core.mjs` with:

```js
export const PINNED_INPUTS = Object.freeze({
  '20260623090000_gm_admin_console.sql':
    'cf9f5912586c08fe7368d51c1cd7a4fb4aef53723298d7a4a92500f71837c271',
  '20260624140000_adaptive_routine_impl.sql':
    '55572dac4d31de589ee7e91a04b2e74ce822c2784beb53389c5b295382956e84',
});

export const FIXTURE_FILENAME =
  '20260623085959_local_replay_admin_fixture.sql';

const FIXTURE_SQL = `-- ADR-0024 local replay fixture; never production
insert into auth.users (id, aud, role, email, created_at, updated_at)
values (
  'b897a59f-0a54-42df-9926-8452e477d8bd',
  'authenticated',
  'authenticated',
  'gm-baseline@example.invalid',
  now(),
  now()
)
on conflict (id) do nothing;
`;
```

Implementation requirements:

1. Resolve `repoRoot`, `supabase`, and the default disposable root with `node:path`.
2. Reject any output whose normalized relative path escapes `repoRoot/supabase/.temp`, equals the boundary itself, or is absolute after `relative()`.
3. Hash both original files with streaming SHA-256 and compare lowercase values before deleting or creating the disposable output.
4. `adaptLegacyRoutineSql()` requires exactly one literal `</loop>`, replaces it with `end loop;`, and returns the adapted SQL plus literal replacement count `1`; `prepareReplayProject()` calls it only after hash verification.
5. After all validation succeeds, remove only the validated disposable root, recreate `<root>/supabase`, and copy:
   - `supabase/config.toml`
   - `supabase/migrations`
   - `supabase/tests`
6. Verify both copied legacy files still match their source bytes before adapting.
7. Write the fixture migration and replace exactly one `</loop>` only in the temporary adaptive migration.
8. Re-hash the two repository source files before returning to prove preparation did not change them.
9. `buildReplayCommands()` returns exactly the two command objects asserted above.
10. `runReplay()` calls `prepareReplayProject()`, then executes commands serially with inherited stdio. The default process runner resolves on exit code `0`, rejects spawn errors, and returns the numeric exit code otherwise. Stop immediately on the first non-zero code.
11. On Windows only, if `DOCKER_HOST` is absent, add `DOCKER_HOST=npipe:////./pipe/docker_engine` to the child environment. Preserve caller environment and never inspect or print credentials.

- [x] **Step 4: Implement the thin CLI and package script**

Create `scripts/local-supabase-replay.mjs`:

```js
#!/usr/bin/env node
import { runReplay } from './local-supabase-replay-core.mjs';

const manifest = await runReplay({ repoRoot: process.cwd() });
console.log(JSON.stringify({
  status: 'pass',
  disposableProjectRoot: manifest.disposableProjectRoot,
  verifiedInputs: manifest.verifiedInputs,
  fixtureMigration: manifest.fixtureMigration,
  patchedMigration: manifest.patchedMigration,
  replacementCount: manifest.replacementCount,
}, null, 2));
```

Wrap the top-level call in `try/catch`, print only `error.message` to stderr, and set `process.exitCode = 1`; never print environment variables, connection strings, or raw database output beyond inherited Supabase CLI output.

Add to `package.json` scripts:

```json
"db:replay:compat": "node scripts/local-supabase-replay.mjs"
```

- [x] **Step 5: Run focused tests and verify GREEN**

Run:

```powershell
npm test -- scripts/local-supabase-replay.test.mjs
```

Expected: all compatibility-harness tests PASS with no warnings.

- [x] **Step 6: Run the real disposable replay**

Run:

```powershell
$env:DOCKER_HOST='npipe:////./pipe/docker_engine'
npm run db:replay:compat
```

Expected:

- both pinned hashes are reported;
- all migrations apply from the disposable project;
- `supabase/tests/routine_safety.sql` passes;
- no linked/production command appears;
- the command exits `0`.

If any additional historical migration fails, stop with `BLOCKED`; ADR-0024 does not authorize silently adding another adaptation.

- [x] **Step 7: Verify source immutability and repository checks**

Run:

```powershell
Get-FileHash -Algorithm SHA256 `
  supabase/migrations/20260623090000_gm_admin_console.sql,`
  supabase/migrations/20260624140000_adaptive_routine_impl.sql
npm run typecheck
npm test
git diff --check
git status --short
```

Expected:

- hashes equal the two Global Constraints values;
- typecheck and full Vitest pass;
- diff check passes;
- only the plan, package script, two harness modules, and harness test are tracked changes.

- [x] **Step 8: Commit**

```powershell
git add package.json `
  scripts/local-supabase-replay-core.mjs `
  scripts/local-supabase-replay.mjs `
  scripts/local-supabase-replay.test.mjs `
  docs/superpowers/plans/2026-07-25-migration-replay-compat.md
git commit -m "test: add local migration replay compatibility harness"
```
