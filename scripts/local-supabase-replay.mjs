#!/usr/bin/env node
import { runReplay } from './local-supabase-replay-core.mjs';

try {
  const manifest = await runReplay({ repoRoot: process.cwd() });

  console.log(JSON.stringify({
    status: 'pass',
    disposableProjectRoot: manifest.disposableProjectRoot,
    verifiedInputs: manifest.verifiedInputs,
    fixtureMigration: manifest.fixtureMigration,
    patchedMigration: manifest.patchedMigration,
    replacementCount: manifest.replacementCount,
  }, null, 2));
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
