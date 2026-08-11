import { createHash } from 'node:crypto';
import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { cp, mkdir, readFile, readdir, realpath, rm, writeFile } from 'node:fs/promises';
import { dirname, isAbsolute, join, relative, resolve, sep } from 'node:path';

export const BASELINE_FILENAME = '20260808160000_baseline_from_production.sql';
export const BASELINE_SHA256 = '4c6b12de4e20ad937aca5ac28b88a073ed39323f5f2e2ef5a756ace92fe6fa26';
export const PROD_EDGE_PREFIX = 'https://byekgmqyqlftgoveqnku.supabase.co/functions/v1/';
export const LOCAL_EDGE_PREFIX = 'http://127.0.0.1:1/functions/v1/';
export const LOCAL_SAFETY_MIGRATION_FILENAME = '20991231235959_local_test_disable_cron.sql';
export const LOCAL_SAFETY_MIGRATION_SQL = `-- Local test safety only; generated in disposable copy, never production.
select cron.alter_job(jobid, null, null, null, null, false)
from cron.job;
`;

function sha256(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

function isWithinOrEqual(root, target) {
  const difference = relative(root, target);
  return !difference
    || (!isAbsolute(difference) && difference !== '..' && !difference.startsWith(`..${sep}`));
}

async function findExistingAncestor(filePath) {
  let candidate = filePath;

  while (true) {
    try {
      return await realpath(candidate);
    } catch (error) {
      if (!['ENOENT', 'ENOTDIR'].includes(error.code)) throw error;
      const parent = resolve(candidate, '..');
      if (parent === candidate) throw error;
      candidate = parent;
    }
  }
}

async function assertDisposableContainment(supabaseRoot, boundary, output) {
  if (!isWithinOrEqual(boundary, output) || output === boundary) {
    throw new Error('Disposable replay output must stay inside supabase/.temp.');
  }

  const [realSupabaseRoot, realOutputAncestor] = await Promise.all([
    realpath(supabaseRoot),
    findExistingAncestor(output),
  ]);
  let realBoundary;

  try {
    realBoundary = await realpath(boundary);
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }

  if (
    (realBoundary && !isWithinOrEqual(realSupabaseRoot, realBoundary))
    || !isWithinOrEqual(realBoundary ?? realSupabaseRoot, realOutputAncestor)
  ) {
    throw new Error('Resolved disposable output must stay inside supabase/.temp.');
  }
}

async function listFiles(root, prefix = '') {
  const files = [];

  for (const entry of await readdir(root, { withFileTypes: true })) {
    const relativePath = join(prefix, entry.name);
    const absolutePath = join(root, entry.name);
    if (entry.isDirectory()) files.push(...await listFiles(absolutePath, relativePath));
    else if (entry.isFile()) files.push(relativePath);
  }

  return files.sort();
}

export function rewriteProductionUrls(source) {
  const count = source.split(PROD_EDGE_PREFIX).length - 1;
  if (count !== 5) throw new Error(`Expected exactly five production Edge URL replacements; found ${count}.`);
  return {
    sql: source.split(PROD_EDGE_PREFIX).join(LOCAL_EDGE_PREFIX),
    replacementCount: count,
  };
}

async function verifyCopiedTree(sourceSupabaseRoot, copiedSupabaseRoot, patchedBaselineBytes) {
  const sourceFiles = [
    'config.toml',
    ...await listFiles(join(sourceSupabaseRoot, 'migrations'), 'migrations'),
    ...await listFiles(join(sourceSupabaseRoot, 'tests'), 'tests'),
  ].sort();
  const copiedFiles = [
    'config.toml',
    ...await listFiles(join(copiedSupabaseRoot, 'migrations'), 'migrations'),
    ...await listFiles(join(copiedSupabaseRoot, 'tests'), 'tests'),
  ].sort();
  const addedRelative = join('migrations', LOCAL_SAFETY_MIGRATION_FILENAME);
  const expectedFiles = [...sourceFiles, addedRelative].sort();

  if (JSON.stringify(copiedFiles) !== JSON.stringify(expectedFiles)) {
    throw new Error('Disposable replay tree contains an unauthorized file change.');
  }

  for (const relativePath of sourceFiles) {
    const source = await readFile(join(sourceSupabaseRoot, relativePath));
    const copied = await readFile(join(copiedSupabaseRoot, relativePath));
    const expected = relativePath === join('migrations', BASELINE_FILENAME)
      ? patchedBaselineBytes
      : source;
    if (!copied.equals(expected)) throw new Error(`Disposable replay copy drift: ${relativePath}.`);
  }

  const safety = await readFile(join(copiedSupabaseRoot, addedRelative), 'utf8');
  if (safety !== LOCAL_SAFETY_MIGRATION_SQL) {
    throw new Error('Disposable local cron safety migration drifted.');
  }
}

export async function prepareSafeReplay({ repoRoot = process.cwd(), disposableProjectRoot } = {}) {
  const resolvedRepoRoot = resolve(repoRoot);
  const sourceSupabaseRoot = join(resolvedRepoRoot, 'supabase');
  const boundary = join(sourceSupabaseRoot, '.temp');
  const output = resolve(disposableProjectRoot ?? join(boundary, 's2-safe-replay', 'project'));
  const sourceBaseline = join(sourceSupabaseRoot, 'migrations', BASELINE_FILENAME);
  const baselineBytes = await readFile(sourceBaseline);
  const baselineHash = sha256(baselineBytes);

  if (baselineHash !== BASELINE_SHA256) {
    throw new Error(`Baseline hash mismatch: expected ${BASELINE_SHA256}, got ${baselineHash}.`);
  }

  await assertDisposableContainment(sourceSupabaseRoot, boundary, output);
  await rm(output, { recursive: true, force: true });
  const copiedSupabaseRoot = join(output, 'supabase');
  await mkdir(copiedSupabaseRoot, { recursive: true });
  await assertDisposableContainment(sourceSupabaseRoot, boundary, output);
  await Promise.all([
    cp(join(sourceSupabaseRoot, 'config.toml'), join(copiedSupabaseRoot, 'config.toml')),
    cp(join(sourceSupabaseRoot, 'migrations'), join(copiedSupabaseRoot, 'migrations'), { recursive: true }),
    cp(join(sourceSupabaseRoot, 'tests'), join(copiedSupabaseRoot, 'tests'), { recursive: true }),
  ]);

  const patchedBaseline = join(copiedSupabaseRoot, 'migrations', BASELINE_FILENAME);
  const rewritten = rewriteProductionUrls(await readFile(patchedBaseline, 'utf8'));
  const patchedBaselineBytes = Buffer.from(rewritten.sql, 'utf8');
  const localSafetyMigration = join(
    copiedSupabaseRoot,
    'migrations',
    LOCAL_SAFETY_MIGRATION_FILENAME,
  );

  await writeFile(patchedBaseline, patchedBaselineBytes);
  await writeFile(localSafetyMigration, LOCAL_SAFETY_MIGRATION_SQL, 'utf8');
  await verifyCopiedTree(sourceSupabaseRoot, copiedSupabaseRoot, patchedBaselineBytes);

  if (sha256(await readFile(sourceBaseline)) !== baselineHash) {
    throw new Error('Source baseline changed during safe replay preparation.');
  }

  return {
    disposableProjectRoot: output,
    patchedBaseline,
    localSafetyMigration,
    replacementCount: rewritten.replacementCount,
    sourceBaselineSha256: baselineHash,
    patchedBaselineSha256: sha256(patchedBaselineBytes),
    addedFiles: [LOCAL_SAFETY_MIGRATION_FILENAME],
  };
}

export function buildReplayCommands(disposableProjectRoot) {
  const command = process.platform === 'win32' ? 'npm.cmd' : 'npm';
  return [
    {
      command,
      args: [
        'exec', '--yes', '--package=supabase@2.109.1', '--',
        'supabase', 'db', 'reset', '--local', '--workdir', disposableProjectRoot, '--no-seed',
      ],
    },
    {
      command,
      args: [
        'exec', '--yes', '--package=supabase@2.109.1', '--',
        'supabase', 'test', 'db', '--local', '--workdir', disposableProjectRoot,
      ],
    },
  ];
}

export function runLocalCommand(command, args, env = process.env) {
  return new Promise((resolveCommand, reject) => {
    let child;
    try {
      const bundledNpmCliPath = join(dirname(process.execPath), 'node_modules', 'npm', 'bin', 'npm-cli.js');
      const npmCliPath = env.npm_execpath
        ?? (existsSync(bundledNpmCliPath) ? bundledNpmCliPath : undefined);
      const useNodeNpmCli = process.platform === 'win32'
        && command.toLowerCase() === 'npm.cmd'
        && npmCliPath;

      if (process.platform === 'win32' && command.toLowerCase() === 'npm.cmd' && !npmCliPath) {
        throw new Error('Unable to resolve npm CLI for Windows local replay.');
      }

      child = spawn(
        useNodeNpmCli ? process.execPath : command,
        useNodeNpmCli ? [npmCliPath, ...args] : args,
        { env, stdio: 'inherit' },
      );
    } catch (error) {
      reject(error);
      return;
    }
    child.once('error', reject);
    child.once('close', (exitCode) => resolveCommand(exitCode ?? 1));
  });
}

export async function runSafeReplay({ repoRoot = process.cwd(), env, spawnImpl = runLocalCommand } = {}) {
  const manifest = await prepareSafeReplay({ repoRoot });
  const childEnv = { ...process.env, ...env };

  if (process.platform === 'win32' && childEnv.DOCKER_HOST === undefined) {
    childEnv.DOCKER_HOST = 'npipe:////./pipe/docker_engine';
  }

  for (const replayCommand of buildReplayCommands(manifest.disposableProjectRoot)) {
    const result = await spawnImpl(replayCommand.command, replayCommand.args, childEnv);
    const exitCode = typeof result === 'number' ? result : result?.exitCode;
    if (exitCode !== 0) throw new Error(`Local replay command failed with exit code ${exitCode}.`);
  }

  return manifest;
}
