# S0 Source-Convergence Inventory

This document records the exact source-convergence inventory generated from the merged isolated worktree `codex/kc-stabilization-s0` at commit `cbe6d8f5549831eb73c96703ae3041b80cb32132`.

## 1. Core Git References

| Reference Type | Git Commit SHA | Description |
| :--- | :--- | :--- |
| **S0_BASE / Merge 1st Parent** | `43636b17fa17be94b7d0e508656f369ac1c2d57a` | Main branch base after S0 resolution |
| **Claude Head / Merge 2nd Parent** | `693e71b73f561d5da9742c108f51af833363a074` | Claude database feature branch HEAD |
| **Pre-merge Common Base** | `666e09ba2ad0ac5a2f9750cf45a259049cfd62b0` | Common ancestor of main and Claude branch |
| **Merged HEAD** | `cbe6d8f5549831eb73c96703ae3041b80cb32132` | Clean non-fast-forward merge commit |

- **Working Directory Status**: Immediately post-merge and prior to report creation, `git status --short` was clean (empty).
- **Ancestry Verification**: All first-parent and second-parent ancestry assertions exit 0 (`merge-base --is-ancestor` passed for all parent commits).

---

## 2. Commit Lists (Common Base Excluded, Oldest First)

### Main-Only Commits (3 commits)
1. `37d78edbe1c3b6af3513d95ab444ce9bca9faf3f` - `docs: define store-first stabilization design`
2. `f8ccde28124c8b23b912f1b7b7a9606570994323` - `docs: plan S0 truth convergence`
3. `43636b17fa17be94b7d0e508656f369ac1c2d57a` - `docs: make S0 base resolution execution-safe`

### Claude-Only Commits (6 commits)
1. `84959eca19e6348ec179a7ce86979538a7cb816d` - `feat(db): make production the baseline, so db push works again`
2. `9f239a12fb80eda78447f916b71bdf4a8356a5ab` - `fix(db): one account that cannot be computed no longer stops the others`
3. `3d05893f275868169e0bb412058c1f36611d33a7` - `feat(db): notice when a scheduled job stops working`
4. `bd276bb3fbe0d9e5398f811063b8319c66344e70` - `fix(db): the alert engine no longer stops for everyone when it trips on one`
5. `85abaf53556e416b352d1dcab8577f6e5f727af7` - `test(db): stop the job-health test depending on whether pg_cron fired`
6. `693e71b73f561d5da9742c108f51af833363a074` - `fix(db): the baseline could not grant access to its own scheduled jobs`

---

## 3. Grouped Changed Paths (Common Base to Merged HEAD)

**Total Changed Paths**: 215

### Path Group Breakdown

| Path Group / Pattern | File Count | Description / Role |
| :--- | :---: | :--- |
| `supabase/migrations-archive/**` | 204 | Archived historical migration files |
| `supabase/migrations/**` (Active) | 5 | Active database schema migrations |
| `supabase/tests/**` | 2 | Local database test suites (pgTAP) |
| `scripts/**` | 1 | Migration extraction utility script |
| `docs/**` | 2 | Superpowers specification and implementation plan |
| Other | 1 | Repository configuration (`.gitattributes`) |

### Active Migrations (5 files)
1. `supabase/migrations/20260808160000_baseline_from_production.sql`
2. `supabase/migrations/20260808230000_per_subject_failure_isolation.sql`
3. `supabase/migrations/20260808234500_scheduled_job_health.sql`
4. `supabase/migrations/20260808235500_alert_path_failure_isolation.sql`
5. `supabase/migrations/20260809001500_extension_schema_grants.sql`

### Other Non-Archive Changed Paths (6 files)
- `.gitattributes`
- `docs/superpowers/plans/2026-08-09-kc-s0-truth-convergence.md`
- `docs/superpowers/specs/2026-08-09-kc-store-first-stabilization-design.md`
- `scripts/extract-ledger-migrations.mjs`
- `supabase/tests/per_subject_failure_isolation.sql`
- `supabase/tests/scheduled_job_health.sql`

### Archive Migrations (204 files)
- 204 archive paths under `supabase/migrations-archive/**` are represented in the diff.

---

## 4. Preserved Ancestry & Clean State Attestation

- **Preserved Ancestry**: Every commit reachable from `S0_BASE` (`43636b17fa17be94b7d0e508656f369ac1c2d57a`) and all 6 Claude-only database commits (`84959ec`, `9f239a1`, `3d05893`, `bd276bb`, `85abaf5`, `693e71b`) remain fully intact as ancestors of `HEAD` (`cbe6d8f5549831eb73c96703ae3041b80cb32132`).
- **Clean Repository State**: Working tree state immediately post-merge (prior to report creation) was completely clean; zero untracked or modified files existed.

---

## 5. Boundary & Compliance Attestation

- **Zero Production / Release Actions**: No git push, tag, deployment, release artifact creation, package version bump, linked Supabase project mutation, remote database execution, or hosted environment operation was run.
- **Redaction Confirmation**: No personal identifiers, passwords, API tokens, secrets, credential-bearing URLs, or production row data are present in this document or evidence inputs.
