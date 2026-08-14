import { createHash } from 'node:crypto';
import { appendFile, cp, mkdtemp, mkdir, readFile, rm, symlink, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { describe, expect, it } from 'vitest';

import {
  adaptLegacyRoutineSql,
  buildReplayCommands,
  prepareReplayProject,
  resolveMigrationsRootFor,
  runLocalCommand,
  runReplay,
  stripLeadingUtf8Bom,
} from './local-supabase-replay-core.mjs';

const REAL_REPO_ROOT = resolve(process.cwd());
// S0 moved the pinned inputs out of supabase/migrations into the archive, so
// ask the harness where they live now rather than naming a directory whose
// meaning has since changed. The fake repositories these tests build still
// receive them as a plain supabase/migrations, which is what the harness
// prefers whenever it is present.
const REAL_MIGRATIONS_ROOT = await resolveMigrationsRootFor(REAL_REPO_ROOT);
const ADMIN_SOURCE = join(
  REAL_MIGRATIONS_ROOT,
  '20260623090000_gm_admin_console.sql',
);
const ADAPTIVE_SOURCE = join(
  REAL_MIGRATIONS_ROOT,
  '20260624140000_adaptive_routine_impl.sql',
);
const BOM_FILENAMES = [
  '20260625174615_sync_activity_truth.sql',
  '20260626072619_scoped_group_activity_views.sql',
];
const PINNED_FILENAMES = [
  '20260623090000_gm_admin_console.sql',
  '20260624140000_adaptive_routine_impl.sql',
  ...BOM_FILENAMES,
];
const DISPOSABLE_PROJECT_ROOT = join(
  REAL_REPO_ROOT,
  'supabase/.temp/replay-compat/project',
);

async function copyReplayInputsToTemp() {
  const fakeRepo = await mkdtemp(join(tmpdir(), 'keep-contact-replay-'));
  const fakeSupabase = join(fakeRepo, 'supabase');

  await cp(join(REAL_REPO_ROOT, 'supabase/config.toml'), join(fakeSupabase, 'config.toml'));
  await cp(REAL_MIGRATIONS_ROOT, join(fakeSupabase, 'migrations'), {
    recursive: true,
  });
  await cp(join(REAL_REPO_ROOT, 'supabase/tests'), join(fakeSupabase, 'tests'), {
    recursive: true,
  });

  return fakeRepo;
}

function sha256(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

async function rewritePinnedLineEndings(repoRoot, newline) {
  for (const filename of PINNED_FILENAMES) {
    const path = join(repoRoot, 'supabase/migrations', filename);
    const source = await readFile(path, 'utf8');
    await writeFile(path, source.replace(/\r?\n/g, newline), 'utf8');
  }
}

describe('local Supabase replay compatibility harness', () => {
  it('prepares a disposable project without changing either source migration', async () => {
    const beforeAdmin = await readFile(ADMIN_SOURCE);
    const beforeAdaptive = await readFile(ADAPTIVE_SOURCE);
    const manifest = await prepareReplayProject({ repoRoot: REAL_REPO_ROOT });

    expect(manifest.replacementCount).toBe(1);
    expect(manifest.replayMode).toBe('folded-baseline');
    expect(await readFile(ADMIN_SOURCE)).toEqual(beforeAdmin);
    expect(await readFile(ADAPTIVE_SOURCE)).toEqual(beforeAdaptive);
    expect(await readFile(manifest.patchedMigration, 'utf8')).not.toContain('</loop>');
    expect(await readFile(manifest.patchedMigration, 'utf8')).toContain('end loop;');
    expect(await readFile(manifest.fixtureMigration, 'utf8')).toContain(
      'b897a59f-0a54-42df-9926-8452e477d8bd',
    );
    const fixtureSql = await readFile(manifest.inspectionFixtureMigration, 'utf8');
    expect(fixtureSql).toContain(
      'grant select on table public.behavior_pings to authenticated;',
    );
    expect(fixtureSql).toContain(
      'grant select on table public.alerts, public.behavior_pings, public.device_state, public.notifications to service_role;',
    );
    expect(fixtureSql).toContain(
      'grant usage on schema cron to service_role;',
    );
    expect(fixtureSql).not.toMatch(
      /\b(?:insert|update|delete|truncate)\s+(?:into\s+|from\s+)?public\./i,
    );
    expect(fixtureSql).toContain(
      'grant select on table cron.job to service_role;',
    );
    expect(fixtureSql).not.toMatch(
      /grant\s+(?:all|insert|update|delete|truncate|references|trigger)\b/i,
    );
  }, 30_000);

  it('strips only the two authorized leading BOMs in the disposable copy', async () => {
    const sources = await Promise.all(BOM_FILENAMES.map((filename) => readFile(
      join(REAL_MIGRATIONS_ROOT, filename),
    )));
    const manifest = await prepareReplayProject({ repoRoot: REAL_REPO_ROOT });

    expect(Object.keys(manifest.verifiedInputs)).toHaveLength(4);

    for (const [index, filename] of BOM_FILENAMES.entries()) {
      const copied = await readFile(join(
        manifest.compatibilityMigrationsRoot,
        filename,
      ));
      const expected = sources[index].subarray(3);
      const action = manifest.compatibilityActions.find((candidate) => (
        candidate.type === 'strip-leading-utf8-bom' && candidate.filename === filename
      ));

      expect(sources[index].subarray(0, 3).toString('hex')).toBe('efbbbf');
      expect(copied.equals(expected)).toBe(true);
      expect(action).toMatchObject({
        filename,
        removedBytes: 3,
        resultingHash: sha256(expected),
      });
    }
  }, 30_000);

  it('accepts identical pinned SQL checked out with LF or CRLF line endings', async () => {
    const lfRepo = await copyReplayInputsToTemp();
    const crlfRepo = await copyReplayInputsToTemp();

    try {
      await rewritePinnedLineEndings(lfRepo, '\n');
      await rewritePinnedLineEndings(crlfRepo, '\r\n');

      await expect(prepareReplayProject({ repoRoot: lfRepo })).resolves.toBeTruthy();
      await expect(prepareReplayProject({ repoRoot: crlfRepo })).resolves.toBeTruthy();
    } finally {
      await rm(lfRepo, { recursive: true, force: true });
      await rm(crlfRepo, { recursive: true, force: true });
    }
  }, 30_000);

  it('fails before replay when a pinned source hash changes', async () => {
    const fakeRepo = await copyReplayInputsToTemp();

    try {
      await appendFile(
        join(fakeRepo, 'supabase/migrations/20260623090000_gm_admin_console.sql'),
        '\n-- drift\n',
      );

      await expect(prepareReplayProject({ repoRoot: fakeRepo }))
        .rejects.toThrow(/hash mismatch.*20260623090000/i);
    } finally {
      await rm(fakeRepo, { recursive: true, force: true });
    }
  });

  it('fails when the authorized token is missing or repeated', () => {
    expect(() => adaptLegacyRoutineSql('begin\nend loop;'))
      .toThrow(/expected exactly one <\/loop> token/i);
    expect(() => adaptLegacyRoutineSql('begin\n</loop>\n</loop>'))
      .toThrow(/expected exactly one <\/loop> token/i);
  });

  it('rejects absent, non-leading, and repeated BOM sequences', () => {
    expect(() => stripLeadingUtf8Bom(Buffer.from('select 1;')))
      .toThrow(/exactly one leading utf-8 bom/i);
    expect(() => stripLeadingUtf8Bom(Buffer.from([0x2d, 0xef, 0xbb, 0xbf])))
      .toThrow(/exactly one leading utf-8 bom/i);
    expect(() => stripLeadingUtf8Bom(Buffer.from([
      0xef, 0xbb, 0xbf, 0xef, 0xbb, 0xbf, 0x2d,
    ]))).toThrow(/exactly one leading utf-8 bom/i);
  });

  it('rejects an additional BOM-bearing repository migration', async () => {
    const fakeRepo = await copyReplayInputsToTemp();

    try {
      await writeFile(
        join(fakeRepo, 'supabase/migrations/20260627000000_unapproved_bom.sql'),
        Buffer.from([0xef, 0xbb, 0xbf, 0x2d, 0x2d]),
      );

      await expect(prepareReplayProject({ repoRoot: fakeRepo }))
        .rejects.toThrow(/unexpected bom.*20260627000000/i);
    } finally {
      await rm(fakeRepo, { recursive: true, force: true });
    }
  });

  it('rejects a disposable output outside supabase/.temp', async () => {
    await expect(prepareReplayProject({
      repoRoot: REAL_REPO_ROOT,
      disposableProjectRoot: join(REAL_REPO_ROOT, 'outside-replay'),
    })).rejects.toThrow(/must stay inside supabase[\\/]\.temp/i);
  });

  it('rejects a disposable path that escapes through a symlink or junction', async () => {
    const fakeRepo = await copyReplayInputsToTemp();
    const outside = await mkdtemp(join(tmpdir(), 'keep-contact-replay-outside-'));
    const escape = join(fakeRepo, 'supabase/.temp/escape');

    try {
      await mkdir(join(fakeRepo, 'supabase/.temp'), { recursive: true });
      await symlink(outside, escape, process.platform === 'win32' ? 'junction' : 'dir');

      await expect(prepareReplayProject({
        repoRoot: fakeRepo,
        disposableProjectRoot: join(escape, 'project'),
      })).rejects.toThrow(/resolved.*supabase[\\/]\.temp/i);
    } finally {
      await rm(fakeRepo, { recursive: true, force: true });
      await rm(outside, { recursive: true, force: true });
    }
  });

  it('builds only pinned local reset, cron freeze, and pgTAP commands', () => {
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
          'supabase', 'db', 'query', '--local',
          '--workdir', DISPOSABLE_PROJECT_ROOT,
          "select cron.unschedule('process-escalations');",
        ],
      },
      {
        command: process.platform === 'win32' ? 'npm.cmd' : 'npm',
        args: [
          'exec', '--yes', '--package=supabase@2.109.1', '--',
          'supabase', 'db', 'query', '--local',
          '--workdir', DISPOSABLE_PROJECT_ROOT,
          "select cron.unschedule('process-checkin-tasks');",
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

  it('starts the Windows npm command through Windows execution rules', async () => {
    if (process.platform !== 'win32') {
      return;
    }

    await expect(runLocalCommand('npm.cmd', ['--version'], process.env))
      .resolves.toBe(0);
  });

  it('preserves a Windows npm argument containing spaces', async () => {
    if (process.platform !== 'win32') {
      return;
    }

    await expect(runLocalCommand('npm.cmd', [
      '--prefix', REAL_REPO_ROOT, '--version',
    ], process.env)).resolves.toBe(0);
  });
});
