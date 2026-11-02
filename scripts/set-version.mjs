// One version number for every surface (human decision 2026-11-02).
//
// PWA, Android APK/AAB, iOS and Tauri all read the same number. A surface left
// on an older number is told that a newer version exists which it cannot
// install — that is how TestFlight 0.7.9 and the 0.7.9 desktop installer were
// prompted to "update" after Android shipped 0.7.10. iOS takes its marketing
// version from APP_VERSION in CI, so it follows automatically.
//
// versionCode (Android) and the iOS build number are monotonic counters, not
// versions; the release scripts / CI own those.
//
// Usage: node scripts/set-version.mjs 0.7.11
import { readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const SOURCES = {
  'src/lib/version.ts': {
    read: (s) => s.match(/APP_VERSION\s*=\s*'([^']+)'/)?.[1],
    write: (s, v) => s.replace(/APP_VERSION\s*=\s*'[^']*'/, `APP_VERSION = '${v}'`),
  },
  'public/version.json': {
    read: (s) => JSON.parse(s).version,
    write: (s, v) => JSON.stringify({ ...JSON.parse(s), version: v }, null, 2) + '\n',
  },
  'android/app/build.gradle': {
    read: (s) => s.match(/versionName\s+"([^"]+)"/)?.[1],
    write: (s, v) => s.replace(/versionName\s+"[^"]*"/, `versionName "${v}"`),
  },
  'src-tauri/tauri.conf.json': {
    read: (s) => JSON.parse(s).version,
    write: (s, v) => s.replace(/("version"\s*:\s*)"[^"]*"/, `$1"${v}"`),
  },
  'src-tauri/Cargo.toml': {
    read: (s) => s.match(/\[package\][\s\S]*?\nversion\s*=\s*"([^"]+)"/)?.[1],
    write: (s, v) => s.replace(/(\[package\][\s\S]*?\nversion\s*=\s*)"[^"]*"/, `$1"${v}"`),
  },
  'src-tauri/Cargo.lock': {
    read: (s) => s.match(/name = "app"\nversion = "([^"]+)"/)?.[1],
    write: (s, v) => s.replace(/(name = "app"\nversion = )"[^"]*"/, `$1"${v}"`),
  },
}

export function readVersions(root) {
  const out = {}
  for (const [rel, src] of Object.entries(SOURCES)) {
    out[rel] = src.read(readFileSync(join(root, rel), 'utf8'))
  }
  return out
}

export function setVersion(root, version) {
  if (!/^\d+\.\d+\.\d+$/.test(version)) throw new Error(`Not a version: ${version}`)
  for (const [rel, src] of Object.entries(SOURCES)) {
    const path = join(root, rel)
    const before = readFileSync(path, 'utf8')
    const after = src.write(before, version)
    if (src.read(after) !== version) throw new Error(`Could not set version in ${rel}`)
    writeFileSync(path, after)
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const version = (process.argv[2] ?? '').replace(/^v/, '')
  const root = join(dirname(fileURLToPath(import.meta.url)), '..')
  setVersion(root, version)
  console.log(`Version set to ${version} in:`, Object.keys(SOURCES).join(', '))
}
