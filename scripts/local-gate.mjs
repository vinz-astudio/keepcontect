import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, readFileSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, '..');

function readText(root, rel, failures) {
  const full = path.join(root, rel);
  if (!existsSync(full)) {
    failures.push({ code: 'MISSING_FILE', message: `${rel} is missing` });
    return null;
  }
  return readFileSync(full, 'utf8');
}

function extract(root, rel, pattern, label, failures) {
  const text = readText(root, rel, failures);
  if (text === null) return null;
  const match = text.match(pattern);
  if (!match) {
    failures.push({ code: 'PARSE_FAILED', message: `Could not parse ${label} from ${rel}` });
    return null;
  }
  return match[1];
}

function fileSha256(file) {
  return createHash('sha256').update(readFileSync(file)).digest('hex');
}

function artifactFact(root, rel) {
  const full = path.join(root, rel);
  if (!existsSync(full)) return null;
  const stat = statSync(full);
  return {
    file: rel,
    bytes: stat.size,
    sha256: fileSha256(full),
  };
}

function hasTauriSigningFallback(text) {
  return /TAURI_SIGNING_PRIVATE_KEY[\s\S]{0,160}\|\|[\s\S]{0,80}['"][^'"]+['"]/.test(text);
}

export function evaluateReleaseGate(root = repoRoot) {
  const failures = [];
  const warnings = [];

  const versions = [
    {
      label: 'app',
      file: 'src/lib/version.ts',
      value: extract(root, 'src/lib/version.ts', /APP_VERSION\s*=\s*['"]([^'"]+)['"]/, 'APP_VERSION', failures),
    },
    {
      label: 'public',
      file: 'public/version.json',
      value: (() => {
        const text = readText(root, 'public/version.json', failures);
        if (text === null) return null;
        try {
          return JSON.parse(text).version ?? null;
        } catch {
          failures.push({ code: 'PARSE_FAILED', message: 'Could not parse public/version.json' });
          return null;
        }
      })(),
    },
    {
      label: 'android',
      file: 'android/app/build.gradle',
      value: extract(root, 'android/app/build.gradle', /versionName\s+["']([^"']+)["']/, 'Android versionName', failures),
    },
    {
      label: 'tauri',
      file: 'src-tauri/tauri.conf.json',
      value: (() => {
        const text = readText(root, 'src-tauri/tauri.conf.json', failures);
        if (text === null) return null;
        try {
          return JSON.parse(text).version ?? null;
        } catch {
          failures.push({ code: 'PARSE_FAILED', message: 'Could not parse src-tauri/tauri.conf.json' });
          return null;
        }
      })(),
    },
    {
      label: 'cargo',
      file: 'src-tauri/Cargo.toml',
      value: extract(root, 'src-tauri/Cargo.toml', /^version\s*=\s*["']([^"']+)["']/m, 'Cargo.toml version', failures),
    },
  ];

  const presentVersions = versions.filter((item) => item.value !== null);
  const uniqueVersions = [...new Set(presentVersions.map((item) => item.value))];
  if (uniqueVersions.length > 1) {
    failures.push({
      code: 'VERSION_MISMATCH',
      message: `Version truth files disagree: ${presentVersions.map((item) => `${item.label}=${item.value}`).join(', ')}`,
    });
  }

  const manifest = readText(root, 'android/app/src/main/AndroidManifest.xml', failures);
  if (manifest !== null) {
    if (/android:allowBackup\s*=\s*["']true["']/.test(manifest)) {
      failures.push({
        code: 'ANDROID_BACKUP_ENABLED',
        message: 'Android backup is enabled; safety-app local data extraction/backup policy must be explicit.',
      });
    } else if (!/android:allowBackup\s*=/.test(manifest)) {
      warnings.push({ code: 'ANDROID_BACKUP_UNSPECIFIED', message: 'Android allowBackup is not explicit.' });
    }
  }

  for (const rel of ['scripts/release.mjs', 'scripts/release-iteration.mjs']) {
    const text = readText(root, rel, failures);
    if (text !== null && hasTauriSigningFallback(text)) {
      failures.push({
        code: 'TAURI_SIGNING_FALLBACK',
        message: `${rel} embeds or falls back to a Tauri signing private key.`,
      });
    }
  }

  if (!process.env.TAURI_SIGNING_PRIVATE_KEY) {
    warnings.push({
      code: 'TAURI_SIGNING_ENV_MISSING',
      message: 'TAURI_SIGNING_PRIVATE_KEY is not set; desktop release must provide it before Tauri build.',
    });
  }

  const artifacts = [
    artifactFact(root, 'public/keep-contact.apk'),
    artifactFact(root, 'public/keep-contact-iteration.apk'),
    artifactFact(root, 'public/desktop/KeepContact-Setup.exe'),
    artifactFact(root, 'public/desktop/KeepContact.msi'),
  ].filter(Boolean);

  return {
    ok: failures.length === 0,
    version: uniqueVersions.length === 1 ? uniqueVersions[0] : null,
    versions,
    artifacts,
    failures,
    warnings,
  };
}

function printResult(result) {
  console.log('Keep Contact local gate');
  console.log(`version: ${result.version ?? 'MISMATCH/UNKNOWN'}`);

  if (result.artifacts.length > 0) {
    console.log('\nArtifacts:');
    for (const artifact of result.artifacts) {
      console.log(`- ${artifact.file}: ${artifact.bytes} bytes sha256=${artifact.sha256}`);
    }
  }

  if (result.warnings.length > 0) {
    console.log('\nWarnings:');
    for (const warning of result.warnings) console.log(`- ${warning.code}: ${warning.message}`);
  }

  if (result.failures.length > 0) {
    console.error('\nFailures:');
    for (const failure of result.failures) console.error(`- ${failure.code}: ${failure.message}`);
  }
}

function run(command, args, cwd = repoRoot) {
  execFileSync(command, args, { cwd, stdio: 'inherit' });
}

function runNpm(args) {
  if (process.env.npm_execpath && existsSync(process.env.npm_execpath)) {
    run(process.execPath, [process.env.npm_execpath, ...args]);
    return;
  }

  if (process.platform === 'win32') {
    run(process.env.ComSpec ?? 'cmd.exe', ['/d', '/s', '/c', `npm ${args.join(' ')}`]);
    return;
  }

  run('npm', args);
}

function runFullGate() {
  runNpm(['run', 'typecheck']);
  runNpm(['test']);
  runNpm(['run', 'build']);

  const vaultRoot = process.env.OBSIDIAN_BRAIN
    ? path.resolve(process.env.OBSIDIAN_BRAIN)
    : path.resolve(repoRoot, '..', '..', 'Obsidian Brain', '2nd Brain');
  const sdlcCheck = path.join(vaultRoot, 'Coordination', 'tools', 'sdlc-check.mjs');
  if (!existsSync(sdlcCheck)) {
    throw new Error(`Brain SDLC check not found: ${sdlcCheck}`);
  }
  run(process.execPath, [sdlcCheck], vaultRoot);
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);

if (isMain) {
  const staticOnly = process.argv.includes('--static-only');
  const result = evaluateReleaseGate(repoRoot);
  printResult(result);

  if (!result.ok) process.exit(1);
  if (!staticOnly) runFullGate();
}
