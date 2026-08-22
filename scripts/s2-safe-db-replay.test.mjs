import { appendFile, cp, mkdir, mkdtemp, readFile, rm, symlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

import {
  BASELINE_FILENAME,
  LOCAL_SAFETY_MIGRATION_FILENAME,
  LOCAL_SAFETY_MIGRATION_SQL,
  PROD_EDGE_PREFIX,
  buildReplayCommands,
  prepareSafeReplay,
  rewriteProductionUrls,
  runLocalCommand,
  runSafeReplay,
} from './s2-safe-db-replay-core.mjs';

const REPO_ROOT = resolve(process.cwd());
const BASELINE = join(REPO_ROOT, 'supabase/migrations', BASELINE_FILENAME);

async function copyInputsToTemp() {
  const root = await mkdtemp(join(tmpdir(), 'kc-s2-safe-replay-'));
  const supabaseRoot = join(root, 'supabase');

  await mkdir(supabaseRoot, { recursive: true });
  await cp(join(REPO_ROOT, 'supabase/config.toml'), join(supabaseRoot, 'config.toml'));
  await cp(join(REPO_ROOT, 'supabase/migrations'), join(supabaseRoot, 'migrations'), { recursive: true });
  await cp(join(REPO_ROOT, 'supabase/tests'), join(supabaseRoot, 'tests'), { recursive: true });
  return root;
}

describe('S2 safe local database replay', () => {
  it('copies inputs, rewrites exactly five production URLs, and leaves source bytes unchanged', async () => {
    const before = await readFile(BASELINE);
    const manifest = await prepareSafeReplay({ repoRoot: REPO_ROOT });
    const copied = await readFile(manifest.patchedBaseline, 'utf8');
    const safety = await readFile(manifest.localSafetyMigration, 'utf8');

    expect(manifest.replacementCount).toBe(5);
    expect(copied).not.toContain(PROD_EDGE_PREFIX);
    expect(copied.match(/http:\/\/127\.0\.0\.1:1\/functions\/v1\//g)).toHaveLength(5);
    expect(safety).toBe(LOCAL_SAFETY_MIGRATION_SQL);
    expect(await readFile(BASELINE)).toEqual(before);
    expect(manifest.addedFiles).toEqual([LOCAL_SAFETY_MIGRATION_FILENAME]);
  }, 30_000);

  it('fails closed when the pinned baseline bytes drift', async () => {
    const fakeRepo = await copyInputsToTemp();

    try {
      await appendFile(join(fakeRepo, 'supabase/migrations', BASELINE_FILENAME), '\n-- drift\n');
      await expect(prepareSafeReplay({ repoRoot: fakeRepo })).rejects.toThrow(/baseline hash mismatch/i);
    } finally {
      await rm(fakeRepo, { recursive: true, force: true });
    }
  }, 30_000);


  it('requires exactly five production URL replacements', () => {
    expect(() => rewriteProductionUrls(`${PROD_EDGE_PREFIX}a`)).toThrow(/exactly five/i);
    expect(() => rewriteProductionUrls(PROD_EDGE_PREFIX.repeat(6))).toThrow(/exactly five/i);
  });

  it('rejects output outside supabase temp and symlink escapes', async () => {
    await expect(prepareSafeReplay({
      repoRoot: REPO_ROOT,
      disposableProjectRoot: join(REPO_ROOT, 'outside-s2-replay'),
    })).rejects.toThrow(/supabase[\\/]\.temp/i);

    const fakeRepo = await copyInputsToTemp();
    const outside = await mkdtemp(join(tmpdir(), 'kc-s2-replay-outside-'));
    const escape = join(fakeRepo, 'supabase/.temp/escape');

    try {
      await mkdir(join(fakeRepo, 'supabase/.temp'), { recursive: true });
      await symlink(outside, escape, process.platform === 'win32' ? 'junction' : 'dir');
      await expect(prepareSafeReplay({
        repoRoot: fakeRepo,
        disposableProjectRoot: join(escape, 'project'),
      })).rejects.toThrow(/resolved.*supabase[\\/]\.temp/i);
    } finally {
      await rm(fakeRepo, { recursive: true, force: true });
      await rm(outside, { recursive: true, force: true });
    }
  });

  it('builds only local reset and local pgTAP commands', () => {
    const commands = buildReplayCommands('C:/safe/replay');
    const encoded = JSON.stringify(commands);

    expect(commands).toHaveLength(2);
    expect(encoded).toContain('db","reset","--local');
    expect(encoded).toContain('test","db","--local');
    expect(encoded).not.toMatch(/--linked|--db-url|db push|migration repair/i);
  });

  it('stops after the first failed local command', async () => {
    const calls = [];
    const spawnImpl = async (command, args) => {
      calls.push([command, args]);
      return { exitCode: 23 };
    };

    await expect(runSafeReplay({ repoRoot: REPO_ROOT, spawnImpl }))
      .rejects.toThrow(/local replay command failed.*23/i);
    expect(calls).toHaveLength(1);
  });

  it('runs npm through the Node CLI on Windows', async () => {
    if (process.platform !== 'win32') return;
    const directNodeEnv = { ...process.env };
    delete directNodeEnv.npm_execpath;
    await expect(runLocalCommand('npm.cmd', ['--version'], directNodeEnv)).resolves.toBe(0);
  });
});
