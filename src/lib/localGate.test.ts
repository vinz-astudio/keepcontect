import { mkdtempSync, rmSync, writeFileSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { afterEach, describe, expect, test } from 'vitest';

type GateFailure = { code: string; message: string };
type GateResult = { ok: boolean; failures: GateFailure[]; version: string | null };
type GateModule = { evaluateReleaseGate: (root: string) => GateResult };

const currentDir = path.dirname(fileURLToPath(import.meta.url));
const gateModuleUrl = pathToFileURL(path.resolve(currentDir, '../../scripts/local-gate.mjs')).href;
const tempRoots: string[] = [];

async function loadGate(): Promise<GateModule> {
  return import(gateModuleUrl) as Promise<GateModule>;
}

function write(root: string, rel: string, content: string) {
  const full = path.join(root, rel);
  mkdirSync(path.dirname(full), { recursive: true });
  writeFileSync(full, content);
}

function makeFixture(overrides: Partial<{
  version: string;
  appVersion: string;
  publicVersion: string;
  androidVersion: string;
  tauriVersion: string;
  cargoVersion: string;
  allowBackup: string;
  releaseScript: string;
  canaryScript: string;
}> = {}) {
  const root = mkdtempSync(path.join(tmpdir(), 'kc-local-gate-'));
  tempRoots.push(root);
  const version = overrides.version ?? '1.2.3';

  write(root, 'src/lib/version.ts', `export const APP_VERSION = '${overrides.appVersion ?? version}'\n`);
  write(root, 'public/version.json', JSON.stringify({ version: overrides.publicVersion ?? version }, null, 2));
  write(root, 'android/app/build.gradle', `android {\n  defaultConfig {\n    versionCode 12\n    versionName "${overrides.androidVersion ?? version}"\n  }\n}\n`);
  write(root, 'src-tauri/tauri.conf.json', JSON.stringify({ version: overrides.tauriVersion ?? version }, null, 2));
  write(root, 'src-tauri/Cargo.toml', `[package]\nname = "app"\nversion = "${overrides.cargoVersion ?? version}"\n`);
  write(root, 'android/app/src/main/AndroidManifest.xml', `<manifest><application android:allowBackup="${overrides.allowBackup ?? 'false'}"></application></manifest>`);
  write(root, 'scripts/release.mjs', overrides.releaseScript ?? 'process.env.TAURI_SIGNING_PRIVATE_KEY\n');
  write(root, 'scripts/release-canary.mjs', overrides.canaryScript ?? 'process.env.TAURI_SIGNING_PRIVATE_KEY\n');
  return root;
}

afterEach(() => {
  while (tempRoots.length > 0) {
    rmSync(tempRoots.pop()!, { recursive: true, force: true });
  }
});

describe('evaluateReleaseGate', () => {
  test('passes when release truth is consistent and security guards are closed', async () => {
    const { evaluateReleaseGate } = await loadGate();
    const root = makeFixture();

    const result = evaluateReleaseGate(root);

    expect(result.ok).toBe(true);
    expect(result.failures).toEqual([]);
    expect(result.version).toBe('1.2.3');
  });

  test('fails on version drift, Android backup, and embedded Tauri signing fallback', async () => {
    const { evaluateReleaseGate } = await loadGate();
    const root = makeFixture({
      publicVersion: '1.2.4',
      allowBackup: 'true',
      releaseScript: "process.env.TAURI_SIGNING_PRIVATE_KEY = process.env.TAURI_SIGNING_PRIVATE_KEY || 'fallback'\n",
    });

    const result = evaluateReleaseGate(root);

    expect(result.ok).toBe(false);
    expect(result.failures).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ code: 'VERSION_MISMATCH' }),
        expect.objectContaining({ code: 'ANDROID_BACKUP_ENABLED' }),
        expect.objectContaining({ code: 'TAURI_SIGNING_FALLBACK' }),
      ]),
    );
  });
});
