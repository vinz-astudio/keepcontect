# Usual Behavior Model v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first production-safe behavior model layer so KC thresholds come from neutral usual behavior evidence, while sensitivity acts as a user-facing adjustment tool.

**Architecture:** Keep the existing `hourly_thresholds` compatibility path, but add a focused pure TypeScript model helper and additive DB metadata fields for confidence/explanation. Edge Function output remains backward-compatible while carrying structured model context. Runtime threshold semantics change so sensitive is near the model baseline, while balanced/relaxed extend it.

**Tech Stack:** React + TypeScript + Vitest, Supabase Postgres migrations, Supabase Edge Function Deno/TypeScript.

---

### Task 1: Sensitivity Tool Semantics

**Files:**
- Modify: `src/features/baseline/types.ts`
- Modify: `src/features/baseline/engine.ts`
- Modify: `src/features/baseline/engine.test.ts`

- [ ] **Step 1: Write failing tests**

Add tests showing:
- `high` threshold is the model baseline plus no more than about 30 minutes.
- `balanced` is longer than `high`.
- `low` is longer than `balanced`.

Run: `npm test -- src/features/baseline/engine.test.ts`
Expected: FAIL because current `SENSITIVITY_PRESETS.high` multiplies baseline by `1.3`.

- [ ] **Step 2: Implement minimal sensitivity tool helper**

Change presets from multiplier/floor semantics to adjustment semantics:
- high: baseline + 0.5h buffer, minimum 1h
- balanced: baseline * 1.35 + 0.5h buffer, minimum 2h
- low: baseline * 1.8 + 1h buffer, minimum 3h

Keep export name stable if possible to avoid broad UI churn.

- [ ] **Step 3: Run focused tests**

Run: `npm test -- src/features/baseline/engine.test.ts`
Expected: PASS.

### Task 2: Pure Usual Model Helper

**Files:**
- Create: `src/features/baseline/usualModel.ts`
- Create: `src/features/baseline/usualModel.test.ts`

- [ ] **Step 1: Write failing tests**

Test that a history of frequent 30-minute awake pings produces:
- enough sample count
- high confidence for active hours
- short p90/p95 gap
- threshold baseline around active gap distribution, independent of sensitivity

Run: `npm test -- src/features/baseline/usualModel.test.ts`
Expected: FAIL because file/function does not exist.

- [ ] **Step 2: Implement pure helper**

Expose:
- `buildUsualBehaviorModel(events, options)`
- `applySensitivityToThreshold(baseHours, sensitivity)`

Model output:
- `hourlyThresholds`
- `hourlyConfidence`
- `gapStatsByHour`
- `sampleCount`
- `modelConfidence`
- `explanation`

- [ ] **Step 3: Run focused tests**

Run: `npm test -- src/features/baseline/usualModel.test.ts`
Expected: PASS.

### Task 3: DB Additive Model Metadata

**Files:**
- Create: `supabase/migrations/20260627133000_usual_behavior_model_v1.sql`

- [ ] **Step 1: Add additive migration**

Add nullable columns to `user_activity_profiles`:
- `model_version text default 'hourly_threshold_v1'`
- `model_confidence double precision`
- `hourly_confidence double precision[]`
- `gap_stats jsonb`
- `model_explanation text`

Rewrite `private.silence_threshold` so sensitivity uses tool semantics:
- `high`: base + 0.5h, floor 1h
- `balanced`: base * 1.35 + 0.5h, floor 2h
- `low`: base * 1.8 + 1h, floor 3h

Keep static fallback if profile missing.

### Task 4: Edge Function Structured Output

**Files:**
- Modify: `supabase/functions/update-routine-profile/index.ts`

- [ ] **Step 1: Extend prompt/schema**

Ask Gemini for neutral baseline plus confidence/explanation. Store all new fields when present.

- [ ] **Step 2: Add rule-based fallback model metadata**

When Gemini fails, compute confidence from gap samples and store basic explanation.

### Task 5: UI Explanation Copy

**Files:**
- Modify: `src/features/baseline/RoutineInsights.tsx`

- [ ] **Step 1: Change copy**

Explain sensitivity as a user tool:
- sensitive: near model threshold
- balanced: waits longer
- relaxed: waits longest

Avoid implying sensitivity changes the learned model.

### Task 6: Verify and Document

**Files:**
- Update Obsidian Project truth and Dev Log after code verification.

- [ ] **Step 1: Run verification**

Run:
- `npm run typecheck`
- `npm test -- --run`
- `npm run build`

- [ ] **Step 2: Update Brain**

Update [[Usual Behavior Model]], [[Alert System]], [[Database Schema]], [[Dev Log]], [[Active Work]].

- [ ] **Step 3: Commit and push**

Stage only related files. Do not stage untracked `AGENTS.md` / `CLAUDE.md`.
