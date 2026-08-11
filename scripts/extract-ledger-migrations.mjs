// Extract every migration's original SQL out of the ledger backup produced by
// `supabase db dump --data-only --schema supabase_migrations`.
//
// The ledger is the only place the pre-baseline history survives in full: 18 of
// the 103 recorded migrations were applied through the dashboard or MCP and have
// no file in supabase/migrations at all. Everything written here is verified
// against md5() computed by the database itself before it is trusted.
//
// Usage: node scripts/extract-ledger-migrations.mjs <backup.sql> <out-dir>

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const [backupPath, outDir] = process.argv.slice(2);
if (!backupPath || !outDir) {
  console.error('usage: extract-ledger-migrations.mjs <backup.sql> <out-dir>');
  process.exit(1);
}

const text = fs.readFileSync(backupPath, 'utf8');

// Locate the single INSERT for schema_migrations and take everything after VALUES.
const insertAt = text.indexOf('INSERT INTO "supabase_migrations"."schema_migrations"');
if (insertAt === -1) throw new Error('no schema_migrations INSERT found in backup');
const valuesAt = text.indexOf('VALUES', insertAt);
if (valuesAt === -1) throw new Error('no VALUES clause found');

// Walk the tuple list character by character. Tracking the SQL string state is
// enough: inside a '...' literal a doubled '' is an escaped quote, and nothing
// else can close it, so parentheses inside SQL bodies cannot confuse the depth.
const body = text.slice(valuesAt + 'VALUES'.length);
const tuples = [];
let depth = 0;
let inString = false;
let current = '';

for (let i = 0; i < body.length; i += 1) {
  const ch = body[i];

  if (inString) {
    if (ch === "'") {
      if (body[i + 1] === "'") { current += "''"; i += 1; continue; }
      inString = false;
    }
    current += ch;
    continue;
  }

  if (ch === "'") { inString = true; current += ch; continue; }
  if (ch === '(') { depth += 1; if (depth === 1) { current = ''; continue; } }
  if (ch === ')') {
    depth -= 1;
    if (depth === 0) { tuples.push(current); current = ''; continue; }
  }
  if (depth === 0) {
    // Between tuples. A semicolon at depth 0 ends the statement.
    if (ch === ';') break;
    continue;
  }
  current += ch;
}

// Split one tuple into its top-level comma-separated SQL literals.
function splitFields(tuple) {
  const fields = [];
  let field = '';
  let inStr = false;
  for (let i = 0; i < tuple.length; i += 1) {
    const ch = tuple[i];
    if (inStr) {
      if (ch === "'") {
        if (tuple[i + 1] === "'") { field += "''"; i += 1; continue; }
        inStr = false;
      }
      field += ch;
      continue;
    }
    if (ch === "'") { inStr = true; field += ch; continue; }
    if (ch === ',') { fields.push(field.trim()); field = ''; continue; }
    field += ch;
  }
  fields.push(field.trim());
  return fields;
}

// '...' -> raw text, undoubling the SQL escape.
function sqlLiteral(token) {
  if (token === 'NULL' || token === 'null') return null;
  if (!token.startsWith("'") || !token.endsWith("'")) {
    throw new Error(`not a quoted literal: ${token.slice(0, 40)}`);
  }
  return token.slice(1, -1).replace(/''/g, "'");
}

// Postgres array literal {"a","b"} -> ['a','b'], undoing \" and \\ inside elements.
function parseArray(literal) {
  if (literal === null) return [];
  const trimmed = literal.trim();
  if (!trimmed.startsWith('{') || !trimmed.endsWith('}')) {
    throw new Error(`not an array literal: ${trimmed.slice(0, 40)}`);
  }
  const inner = trimmed.slice(1, -1);
  const out = [];
  let i = 0;
  while (i < inner.length) {
    while (i < inner.length && (inner[i] === ',' || inner[i] === ' ' || inner[i] === '\n')) i += 1;
    if (i >= inner.length) break;
    if (inner[i] !== '"') throw new Error('unquoted array element is not expected here');
    i += 1;
    let element = '';
    while (i < inner.length) {
      const ch = inner[i];
      if (ch === '\\') { element += inner[i + 1]; i += 2; continue; }
      if (ch === '"') { i += 1; break; }
      element += ch;
      i += 1;
    }
    out.push(element);
  }
  return out;
}

fs.mkdirSync(outDir, { recursive: true });

const manifest = [];
for (const tuple of tuples) {
  const fields = splitFields(tuple);
  if (fields.length < 3) throw new Error(`unexpected tuple shape: ${fields.length} fields`);
  const version = sqlLiteral(fields[0]);
  const statements = parseArray(sqlLiteral(fields[1]));
  const name = sqlLiteral(fields[2]);

  // Statements are stored split; rejoining with a blank line reproduces a
  // runnable file without claiming it is byte-identical to any original file.
  const sql = statements.join('\n\n');
  const safeName = (name || 'unnamed').replace(/^\d{14}_/, '').replace(/[^a-zA-Z0-9_-]/g, '_');
  const file = `${version}_${safeName}.sql`;
  fs.writeFileSync(path.join(outDir, file), sql, 'utf8');

  manifest.push({
    version,
    name,
    file,
    statement_count: statements.length,
    // md5 of each statement, so the database can confirm the extraction is faithful
    statement_md5: statements.map((s) => crypto.createHash('md5').update(s, 'utf8').digest('hex')),
  });
}

fs.writeFileSync(path.join(outDir, '_manifest.json'), JSON.stringify(manifest, null, 2), 'utf8');
console.log(JSON.stringify({
  tuples: tuples.length,
  files: manifest.length,
  total_statements: manifest.reduce((n, m) => n + m.statement_count, 0),
}));
