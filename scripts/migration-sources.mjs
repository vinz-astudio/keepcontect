import fs from 'node:fs'
import path from 'node:path'

// S0 replaced ninety-nine per-file migrations with one baseline generated from
// production, and moved the history into supabase/migrations-archive:
//
//   as-applied/  what production actually ran
//   from-repo/   what the repository held
//
// The two are not the same set — a file present only in from-repo is a
// migration that was written but never reached production, which is the drift
// S0 existed to find.
//
// Contract tests that assert on a historical migration's text broke silently
// when their files moved: readdirSync found nothing, the filter returned an
// empty array, and the assertion failed with "expected 0 to be 1" rather than
// anything that said "your source moved". These helpers make the lookup
// explicit about which history it is reading, and fail loudly when a named
// migration exists in neither place.

export const LIVE_DIR = 'supabase/migrations'
export const ARCHIVE_AS_APPLIED = 'supabase/migrations-archive/as-applied'
export const ARCHIVE_FROM_REPO = 'supabase/migrations-archive/from-repo'

/**
 * Find migrations whose filename contains `fragment`, searching the live set
 * first and then the archives. Returns absolute paths plus the origin, so a
 * caller can tell "still shipping" from "history only".
 */
export function findMigrations(fragment, { root = process.cwd() } = {}) {
  const found = []
  for (const [origin, dir] of [
    ['live', LIVE_DIR],
    ['as-applied', ARCHIVE_AS_APPLIED],
    ['from-repo', ARCHIVE_FROM_REPO],
  ]) {
    const abs = path.resolve(root, dir)
    if (!fs.existsSync(abs)) continue
    for (const file of fs.readdirSync(abs)) {
      if (file.includes(fragment)) {
        found.push({ origin, file, path: path.join(abs, file) })
      }
    }
  }
  return found
}

/**
 * Read exactly one historical migration by filename fragment. Throws with the
 * places searched when the fragment matches nothing, so a moved file reports
 * itself instead of degrading into an empty-array assertion failure.
 */
export function readHistoricalMigration(fragment, { root = process.cwd(), origin } = {}) {
  const matches = findMigrations(fragment, { root })
    .filter((entry) => (origin ? entry.origin === origin : true))
  if (matches.length === 0) {
    throw new Error(
      `no migration matching "${fragment}"${origin ? ` in ${origin}` : ''}; searched ` +
        [LIVE_DIR, ARCHIVE_AS_APPLIED, ARCHIVE_FROM_REPO].join(', '),
    )
  }
  const names = new Set(matches.map((entry) => entry.file))
  if (names.size > 1) {
    throw new Error(
      `"${fragment}" matches more than one migration: ${[...names].join(', ')}`,
    )
  }
  const preferred =
    matches.find((entry) => entry.origin === 'live')
    ?? matches.find((entry) => entry.origin === 'from-repo')
    ?? matches[0]
  return {
    ...preferred,
    sql: fs.readFileSync(preferred.path, 'utf8'),
  }
}

/** Every migration that still ships, in the order Postgres would replay them. */
export function listLiveMigrations({ root = process.cwd() } = {}) {
  const abs = path.resolve(root, LIVE_DIR)
  return fs
    .readdirSync(abs)
    .filter((file) => file.endsWith('.sql'))
    .sort()
    .map((file) => ({ file, path: path.join(abs, file) }))
}

// The production baseline is pg_dump output, so every identifier is quoted:
//   CREATE OR REPLACE FUNCTION "private"."capture_alert_shadow_interventions"(
// while hand-written migrations are not. Both forms have to match, and the
// captured name has to come back unquoted so callers can test it plainly.
const FUNCTION_HEADER =
  /create\s+(?:or\s+replace\s+)?function\s+"?([a-z_]+)"?\s*\.\s*"?([a-z0-9_]+)"?\s*\(/gi

/**
 * Extract each CREATE FUNCTION block from the migrations that still ship, for
 * every function whose `schema.name` matches `namePattern`.
 *
 * Blocks are cut at dollar-quote boundaries rather than at the next CREATE, so
 * a body that legitimately mentions CREATE is not truncated mid-function.
 */
export function extractLiveFunctionBodies(namePattern, { root = process.cwd() } = {}) {
  const blocks = []
  for (const { file, path: abs } of listLiveMigrations({ root })) {
    const sql = fs.readFileSync(abs, 'utf8')
    const header = new RegExp(FUNCTION_HEADER.source, 'gi')
    let match
    while ((match = header.exec(sql)) !== null) {
      const qualified = `${match[1]}.${match[2]}`
      if (!namePattern.test(qualified)) continue
      // A function may be declared with LANGUAGE sql and no dollar quoting at
      // all; take the statement up to the next semicolon at line start in that
      // case rather than skipping it silently.
      const rest = sql.slice(match.index)
      const tagMatch = /\$([a-z_]*)\$/i.exec(rest)
      let body
      if (tagMatch) {
        const tag = tagMatch[0]
        const bodyStart = match.index + tagMatch.index + tag.length
        const bodyEnd = sql.indexOf(tag, bodyStart)
        body = bodyEnd === -1
          ? rest
          : sql.slice(match.index, bodyEnd + tag.length)
        header.lastIndex = bodyEnd === -1 ? sql.length : bodyEnd + tag.length
      } else {
        const stop = sql.indexOf('\n;', match.index)
        body = sql.slice(match.index, stop === -1 ? sql.length : stop)
      }
      blocks.push({ file, name: qualified, body })
    }
  }
  return blocks
}
