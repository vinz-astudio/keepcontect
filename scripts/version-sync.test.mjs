import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { describe, expect, test } from 'vitest'
import { readVersions, setVersion } from './set-version.mjs'

// Human decision 2026-11-02: one version number for every surface (PWA, Android
// APK/AAB, iOS, Tauri). A surface left on an older number is told a newer
// version exists that it cannot install, which is a false update prompt.
describe('one version number across every surface', () => {
  test('all version sources in the repository agree', () => {
    const versions = readVersions(process.cwd())
    const distinct = [...new Set(Object.values(versions))]
    expect(versions, JSON.stringify(versions)).toBeTruthy()
    expect(distinct).toHaveLength(1)
  })

  test('setVersion moves every source together and leaves versionCode to the release script', () => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'kc-version-'))
    const copy = (rel) => {
      fs.mkdirSync(path.dirname(path.join(tmp, rel)), { recursive: true })
      fs.copyFileSync(path.join(process.cwd(), rel), path.join(tmp, rel))
    }
    for (const rel of ['src/lib/version.ts', 'public/version.json', 'android/app/build.gradle',
      'src-tauri/tauri.conf.json', 'src-tauri/Cargo.toml', 'src-tauri/Cargo.lock']) copy(rel)
    const codeBefore = fs.readFileSync(path.join(tmp, 'android/app/build.gradle'), 'utf8').match(/versionCode\s+(\d+)/)[1]
    setVersion(tmp, '9.8.7')
    expect(Object.values(readVersions(tmp))).toEqual(Array(6).fill('9.8.7'))
    const after = fs.readFileSync(path.join(tmp, 'android/app/build.gradle'), 'utf8')
    expect(after.match(/versionCode\s+(\d+)/)[1]).toBe(codeBefore)
    // Only the app crate's lock entry moves; dependencies keep their versions.
    const lock = fs.readFileSync(path.join(tmp, 'src-tauri/Cargo.lock'), 'utf8')
    expect(lock.match(/name = "app"\nversion = "([^"]+)"/)[1]).toBe('9.8.7')
    expect(lock.split('version = "9.8.7"').length - 1).toBe(1)
    fs.rmSync(tmp, { recursive: true, force: true })
  })

  test('the Android release script uses the shared setter, so Tauri can no longer be left behind', () => {
    const script = fs.readFileSync(path.join(process.cwd(), 'scripts/release-android.mjs'), 'utf8')
    expect(script).toMatch(/from '\.\/set-version\.mjs'/)
    expect(script).toMatch(/setVersion\(root, versionName\)/)
  })
})
