import { createHash } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { cp, mkdir, readFile, readdir, realpath, rm, writeFile } from 'node:fs/promises';
import { isAbsolute, join, relative, resolve, sep } from 'node:path';
import { spawn } from 'node:child_process';

export const PINNED_INPUTS = Object.freeze({
  '20260623090000_gm_admin_console.sql':
    'cf9f5912586c08fe7368d51c1cd7a4fb4aef53723298d7a4a92500f71837c271',
  '20260624140000_adaptive_routine_impl.sql':
    '55572dac4d31de589ee7e91a04b2e74ce822c2784beb53389c5b295382956e84',
  '20260625174615_sync_activity_truth.sql':
    '0c92784730710fe1b487c01f8199115f1fc7053238e4607c52428e2cb45a2090',
  '20260626072619_scoped_group_activity_views.sql':
    'bca5cd87009bba29e5906487322af56ca99c30db1d9717113886f347dbec85ff',
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

const UTF8_BOM = Buffer.from([0xef, 0xbb, 0xbf]);
const BOM_FILENAMES = Object.freeze([
  '20260625174615_sync_activity_truth.sql',
  '20260626072619_scoped_group_activity_views.sql',
]);
const BOM_FILENAME_SET = new Set(BOM_FILENAMES);

async function hashFile(filePath) {
  const hash = createHash('sha256');

  for await (const chunk of createReadStream(filePath)) {
    hash.update(chunk);
  }

  return hash.digest('hex');
}

function resolveDisposableProjectRoot(repoRoot, disposableProjectRoot) {
  const supabaseRoot = resolve(repoRoot, 'supabase');
  const boundary = resolve(supabaseRoot, '.temp');
  const output = resolve(
    disposableProjectRoot ?? join(boundary, 'replay-compat', 'project'),
  );
  const outputRelativeToBoundary = relative(boundary, output);

  if (
    !outputRelativeToBoundary
    || isAbsolute(outputRelativeToBoundary)
    || outputRelativeToBoundary === '..'
    || outputRelativeToBoundary.startsWith(`..${sep}`)
  ) {
    throw new Error('Disposable replay output must stay inside supabase/.temp.');
  }

  return { output, supabaseRoot };
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
      if (!['ENOENT', 'ENOTDIR'].includes(error.code)) {
        throw error;
      }

      const parent = resolve(candidate, '..');
      if (parent === candidate) {
        throw error;
      }
      candidate = parent;
    }
  }
}

async function assertResolvedDisposableContainment(supabaseRoot, boundary, output) {
  const [realSupabaseRoot, realOutputAncestor] = await Promise.all([
    realpath(supabaseRoot),
    findExistingAncestor(output),
  ]);
  let realBoundary;

  try {
    realBoundary = await realpath(boundary);
  } catch (error) {
    if (error.code !== 'ENOENT') {
      throw error;
    }
  }

  if (
    (realBoundary && !isWithinOrEqual(realSupabaseRoot, realBoundary))
    || !isWithinOrEqual(realBoundary ?? realSupabaseRoot, realOutputAncestor)
  ) {
    throw new Error('Resolved disposable output must stay inside supabase/.temp.');
  }
}

async function verifyPinnedInputs(migrationsRoot) {
  const verifiedInputs = {};

  for (const [filename, expectedHash] of Object.entries(PINNED_INPUTS)) {
    const actualHash = await hashFile(join(migrationsRoot, filename));

    if (actualHash.toLowerCase() !== expectedHash.toLowerCase()) {
      throw new Error(`Pinned source hash mismatch: ${filename}.`);
    }

    verifiedInputs[filename] = actualHash;
  }

  return verifiedInputs;
}

export function stripLeadingUtf8Bom(sourceBytes) {
  const firstBom = sourceBytes.subarray(0, UTF8_BOM.length);
  const hasAdditionalBom = sourceBytes.indexOf(UTF8_BOM, UTF8_BOM.length) !== -1;

  if (!firstBom.equals(UTF8_BOM) || hasAdditionalBom) {
    throw new Error('Expected exactly one leading UTF-8 BOM.');
  }

  return sourceBytes.subarray(UTF8_BOM.length);
}

async function verifyAuthorizedBomInputs(migrationsRoot) {
  const sources = new Map();

  for (const filename of BOM_FILENAMES) {
    const source = await readFile(join(migrationsRoot, filename));
    stripLeadingUtf8Bom(source);
    sources.set(filename, source);
  }

  for (const entry of await readdir(migrationsRoot, { withFileTypes: true })) {
    if (!entry.isFile() || !entry.name.endsWith('.sql') || BOM_FILENAME_SET.has(entry.name)) {
      continue;
    }

    const bytes = await readFile(join(migrationsRoot, entry.name));
    if (bytes.subarray(0, UTF8_BOM.length).equals(UTF8_BOM)) {
      throw new Error(`Unexpected BOM-bearing migration: ${entry.name}.`);
    }
  }

  return sources;
}

async function verifyCopiedSources(sourceMigrationsRoot, copiedMigrationsRoot) {
  for (const filename of Object.keys(PINNED_INPUTS)) {
    const [source, copied] = await Promise.all([
      readFile(join(sourceMigrationsRoot, filename)),
      readFile(join(copiedMigrationsRoot, filename)),
    ]);

    if (!source.equals(copied)) {
      throw new Error(`Copied migration differs from source: ${filename}.`);
    }
  }
}

async function listFiles(root, prefix = '') {
  const files = [];

  for (const entry of await readdir(root, { withFileTypes: true })) {
    const relativePath = join(prefix, entry.name);
    const absolutePath = join(root, entry.name);

    if (entry.isDirectory()) {
      files.push(...await listFiles(absolutePath, relativePath));
    } else if (entry.isFile()) {
      files.push(relativePath);
    }
  }

  return files;
}

async function verifyCopiedTree(sourceSupabaseRoot, copiedSupabaseRoot, adaptedRoutine) {
  const sourceFiles = [
    'config.toml',
    ...await listFiles(join(sourceSupabaseRoot, 'migrations'), 'migrations'),
    ...await listFiles(join(sourceSupabaseRoot, 'tests'), 'tests'),
  ];
  const copiedFiles = [
    'config.toml',
    ...await listFiles(join(copiedSupabaseRoot, 'migrations'), 'migrations'),
    ...await listFiles(join(copiedSupabaseRoot, 'tests'), 'tests'),
  ];
  const expectedFiles = new Set([
    ...sourceFiles,
    join('migrations', FIXTURE_FILENAME),
  ]);

  if (
    copiedFiles.length !== expectedFiles.size
    || copiedFiles.some((relativePath) => !expectedFiles.has(relativePath))
  ) {
    throw new Error('Copied tree contains an unauthorized file change.');
  }

  for (const relativePath of sourceFiles) {
    const source = await readFile(join(sourceSupabaseRoot, relativePath));
    let expected = source;

    if (relativePath === join('migrations', '20260624140000_adaptive_routine_impl.sql')) {
      expected = Buffer.from(adaptedRoutine.sql, 'utf8');
    } else if (relativePath.startsWith(`migrations${sep}`)) {
      const filename = relativePath.slice(`migrations${sep}`.length);
      if (BOM_FILENAME_SET.has(filename)) {
        expected = stripLeadingUtf8Bom(source);
      }
    }

    const copied = await readFile(join(copiedSupabaseRoot, relativePath));
    if (!copied.equals(expected)) {
      throw new Error(`Copied tree differs outside authorized adaptations: ${relativePath}.`);
    }
  }

  const fixture = await readFile(join(copiedSupabaseRoot, 'migrations', FIXTURE_FILENAME));
  if (!fixture.equals(Buffer.from(FIXTURE_SQL, 'utf8'))) {
    throw new Error('Copied tree fixture differs from the authorized fixture.');
  }
}

export function adaptLegacyRoutineSql(sourceText) {
  const matches = sourceText.match(/<\/loop>/g) ?? [];

  if (matches.length !== 1) {
    throw new Error('Expected exactly one </loop> token in the legacy routine SQL.');
  }

  return {
    sql: sourceText.replace('</loop>', 'end loop;'),
    replacementCount: 1,
  };
}

export async function prepareReplayProject({ repoRoot, disposableProjectRoot } = {}) {
  const resolvedRepoRoot = resolve(repoRoot);
  const { output, supabaseRoot } = resolveDisposableProjectRoot(
    resolvedRepoRoot,
    disposableProjectRoot,
  );
  const migrationsRoot = join(supabaseRoot, 'migrations');
  const boundary = join(supabaseRoot, '.temp');
  const verifiedInputs = await verifyPinnedInputs(migrationsRoot);
  const bomSources = await verifyAuthorizedBomInputs(migrationsRoot);
  const disposableSupabaseRoot = join(output, 'supabase');
  const disposableMigrationsRoot = join(disposableSupabaseRoot, 'migrations');

  await assertResolvedDisposableContainment(supabaseRoot, boundary, output);
  await rm(output, { recursive: true, force: true });
  await mkdir(disposableSupabaseRoot, { recursive: true });
  await assertResolvedDisposableContainment(supabaseRoot, boundary, output);
  await Promise.all([
    cp(join(supabaseRoot, 'config.toml'), join(disposableSupabaseRoot, 'config.toml')),
    cp(migrationsRoot, disposableMigrationsRoot, { recursive: true }),
    cp(join(supabaseRoot, 'tests'), join(disposableSupabaseRoot, 'tests'), { recursive: true }),
  ]);

  await verifyCopiedSources(migrationsRoot, disposableMigrationsRoot);

  const fixtureMigration = join(disposableMigrationsRoot, FIXTURE_FILENAME);
  const patchedMigration = join(
    disposableMigrationsRoot,
    '20260624140000_adaptive_routine_impl.sql',
  );
  const adaptedRoutine = adaptLegacyRoutineSql(await readFile(patchedMigration, 'utf8'));
  const compatibilityActions = [];

  await writeFile(fixtureMigration, FIXTURE_SQL, 'utf8');
  await writeFile(patchedMigration, adaptedRoutine.sql, 'utf8');
  compatibilityActions.push({
    type: 'add-local-admin-fixture',
    filename: FIXTURE_FILENAME,
    resultingHash: await hashFile(fixtureMigration),
  });
  compatibilityActions.push({
    type: 'replace-legacy-loop-token',
    filename: '20260624140000_adaptive_routine_impl.sql',
    replacementCount: adaptedRoutine.replacementCount,
    resultingHash: await hashFile(patchedMigration),
  });

  for (const filename of BOM_FILENAMES) {
    const patchedBomMigration = join(disposableMigrationsRoot, filename);
    const adaptedBom = stripLeadingUtf8Bom(bomSources.get(filename));

    await writeFile(patchedBomMigration, adaptedBom);
    compatibilityActions.push({
      type: 'strip-leading-utf8-bom',
      filename,
      removedBytes: UTF8_BOM.length,
      resultingHash: await hashFile(patchedBomMigration),
    });
  }

  await verifyCopiedTree(supabaseRoot, disposableSupabaseRoot, adaptedRoutine);
  const verifiedAfter = await verifyPinnedInputs(migrationsRoot);

  if (JSON.stringify(verifiedAfter) !== JSON.stringify(verifiedInputs)) {
    throw new Error('Pinned source hashes changed during replay preparation.');
  }

  return {
    disposableProjectRoot: output,
    verifiedInputs,
    fixtureMigration,
    patchedMigration,
    replacementCount: adaptedRoutine.replacementCount,
    compatibilityActions,
  };
}

export function buildReplayCommands(disposableProjectRoot) {
  const command = process.platform === 'win32' ? 'npm.cmd' : 'npm';

  return [
    {
      command,
      args: [
        'exec', '--yes', '--package=supabase@2.109.1', '--',
        'supabase', 'db', 'reset', '--local',
        '--workdir', disposableProjectRoot, '--no-seed',
      ],
    },
    {
      command,
      args: [
        'exec', '--yes', '--package=supabase@2.109.1', '--',
        'supabase', 'test', 'db', '--local',
        '--workdir', disposableProjectRoot,
      ],
    },
  ];
}

export function runLocalCommand(command, args, env) {
  return new Promise((resolveCommand, reject) => {
    let child;

    try {
      const npmCliPath = env?.npm_execpath ?? process.env.npm_execpath;
      const useNodeNpmCli = process.platform === 'win32'
        && command.toLowerCase() === 'npm.cmd'
        && npmCliPath;
      const executable = useNodeNpmCli ? process.execPath : command;
      const executableArgs = useNodeNpmCli ? [npmCliPath, ...args] : args;

      child = spawn(executable, executableArgs, {
        env,
        stdio: 'inherit',
      });
    } catch (error) {
      reject(error);
      return;
    }

    child.once('error', reject);
    child.once('close', (exitCode) => resolveCommand(exitCode ?? 1));
  });
}

export async function runReplay({ repoRoot, env, spawnImpl = runLocalCommand } = {}) {
  const manifest = await prepareReplayProject({ repoRoot });
  const childEnv = { ...process.env, ...env };

  if (process.platform === 'win32' && childEnv.DOCKER_HOST === undefined) {
    childEnv.DOCKER_HOST = 'npipe:////./pipe/docker_engine';
  }

  for (const replayCommand of buildReplayCommands(manifest.disposableProjectRoot)) {
    const result = await spawnImpl(replayCommand.command, replayCommand.args, childEnv);
    const exitCode = typeof result === 'number' ? result : result?.exitCode;

    if (exitCode !== 0) {
      throw new Error(`Local replay command failed with exit code ${exitCode}.`);
    }
  }

  return manifest;
}
