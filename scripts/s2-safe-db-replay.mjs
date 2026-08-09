#!/usr/bin/env node
import { runSafeReplay } from './s2-safe-db-replay-core.mjs';

try {
  const manifest = await runSafeReplay({ repoRoot: process.cwd() });
  console.log(JSON.stringify({ status: 'pass', ...manifest }, null, 2));
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
