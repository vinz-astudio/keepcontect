// scripts/release-iteration.mjs
// Iteration-branch release script. Builds APK + Tauri desktop installers for the GM test environment.
// All binaries are named with "-iteration" suffix and hosted at the iteration Vercel URL.
// Usage: node scripts/release-iteration.mjs <versionName>   Example: node scripts/release-iteration.mjs 0.5.7-iter.1

import { execSync } from 'node:child_process'
import { readFileSync, writeFileSync, copyFileSync, existsSync, mkdirSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const ITERATION_URL = 'https://keep-contact-git-iteration-vinzastudio-3665s-projects.vercel.app'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const run = (cmd, opts = {}) =>
  execSync(cmd, { stdio: 'inherit', cwd: root, ...opts })

// Inject signing private key for Tauri updater
process.env.TAURI_SIGNING_PRIVATE_KEY = process.env.TAURI_SIGNING_PRIVATE_KEY || 'dW50cnVzdGVkIGNvbW1lbnQ6IHJzaWduIGVuY3J5cHRlZCBzZWNyZXQga2V5ClJXUlRZMEl5TXJ6aGFwQ2FjZzBoK1RGNDcvdGVOSzVselFMMytTSjdUQUkrcnUyKzFFTUFBQkFBQUFBQUFBQUFBQUlBQUFBQUxVRnQwL2tFWFZJV3YwbXlRcWJDaTBjOUxPNmRsV3JOeEIrVkpHV2ZSSjFsQXlwUXRSVFcvMU1tV21lQzBpWnZvRlI0Zi9HTnlZK3R3VXlrdE9LZzl3RnBGdUs5N2YvUUxyN1pBdklWdnFmQW5BbTZueFM3M3RSZmNpdXAwSHdPdklGVkQ4UENkMUk9Cg=='

const arg = process.argv[2]
if (!arg) {
  console.error('Usage: node scripts/release-iteration.mjs <versionName>   Example: 0.5.7-iter.1')
  process.exit(1)
}
const tag = arg.startsWith('v') ? arg : `v${arg}`
const versionName = tag.replace(/^v/, '')

console.log(`\n🔁 Keep Contact — ITERATION Release: ${versionName}\n`)
console.log(`   Hosted at: ${ITERATION_URL}\n`)

// 1. Bump version in src/lib/version.ts (keeps LATEST_URL pointing to iteration)
console.log('1. Bumping version in src/lib/version.ts...')
const verTsPath = join(root, 'src/lib/version.ts')
if (existsSync(verTsPath)) {
  let verTs = readFileSync(verTsPath, 'utf8')
  verTs = verTs.replace(/APP_VERSION\s*=\s*'[^']*'/, `APP_VERSION = '${versionName}'`)
  // Ensure LATEST_URL stays on iteration domain (guard against accidental overwrite)
  if (!verTs.includes(ITERATION_URL)) {
    verTs = verTs.replace(
      /LATEST_URL\s*=\s*'[^']*'/,
      `LATEST_URL = '${ITERATION_URL}/version.json'`
    )
  }
  writeFileSync(verTsPath, verTs)
  console.log(`   ✓ APP_VERSION = '${versionName}'`)
}

// 2. Bump version.json (iteration-specific binary URLs)
console.log('2. Updating public/version.json...')
const verJsonPath = join(root, 'public/version.json')
const verJson = {
  version: versionName,
  apkUrl: `${ITERATION_URL}/keep-contact-iteration.apk`,
  exeUrl: `${ITERATION_URL}/desktop/KeepContact-Iteration-Setup.exe`,
}
writeFileSync(verJsonPath, JSON.stringify(verJson, null, 2) + '\n')
console.log(`   ✓ version.json updated for iteration`)

// 3. Bump src-tauri/tauri.conf.json
console.log('3. Bumping src-tauri/tauri.conf.json...')
const tauriConfPath = join(root, 'src-tauri/tauri.conf.json')
if (existsSync(tauriConfPath)) {
  const tauriConf = JSON.parse(readFileSync(tauriConfPath, 'utf8'))
  tauriConf.version = versionName
  writeFileSync(tauriConfPath, JSON.stringify(tauriConf, null, 2) + '\n')
  console.log(`   ✓ tauri.conf.json version = '${versionName}'`)
}

// 4. Bump src-tauri/Cargo.toml
console.log('4. Bumping src-tauri/Cargo.toml...')
const cargoTomlPath = join(root, 'src-tauri/Cargo.toml')
if (existsSync(cargoTomlPath)) {
  let cargoToml = readFileSync(cargoTomlPath, 'utf8')
  cargoToml = cargoToml.replace(/^version\s*=\s*"[^"]*"/m, `version = "${versionName}"`)
  writeFileSync(cargoTomlPath, cargoToml)
  console.log(`   ✓ Cargo.toml version = "${versionName}"`)
}

// 5. Bump android/app/build.gradle
console.log('5. Bumping android/app/build.gradle...')
const gradlePath = join(root, 'android/app/build.gradle')
if (existsSync(gradlePath)) {
  let gradle = readFileSync(gradlePath, 'utf8')
  const m = gradle.match(/versionCode\s+(\d+)/)
  if (m) {
    const nextCode = parseInt(m[1], 10) + 1
    gradle = gradle
      .replace(/versionCode\s+\d+/, `versionCode ${nextCode}`)
      .replace(/versionName\s+"[^"]*"/, `versionName "${versionName}"`)
    writeFileSync(gradlePath, gradle)
    console.log(`   ✓ versionCode → ${nextCode}, versionName → "${versionName}"`)
  }
}

// 6. Build Web app
console.log('\n6. Building Web application...')
run('npm run build')
run('node scripts/clean-tauri-dist.js')

// 7. Sync and Build Android APK → keep-contact-iteration.apk
console.log('\n7. Building iteration Android APK...')
const gradlewPath = join(root, 'android', process.platform === 'win32' ? 'gradlew.bat' : 'gradlew')
if (existsSync(gradlewPath)) {
  try {
    run('npx cap sync android')
    const gradlew = process.platform === 'win32' ? `"${gradlewPath}"` : './gradlew'
    run(`${gradlew} assembleRelease --console=plain`, { cwd: join(root, 'android') })

    const builtApk = join(root, 'android/app/build/outputs/apk/release/app-release.apk')
    const destApk = join(root, 'public/keep-contact-iteration.apk')
    if (existsSync(builtApk)) {
      copyFileSync(builtApk, destApk)
      console.log(`   ✓ APK → ${destApk}`)
    } else {
      console.warn('   ⚠ Built APK not found!')
    }
  } catch (err) {
    console.error('   ✗ Android build failed:', err.message)
  }
} else {
  console.log('   - Gradlew not found. Skipping Android build.')
}

// 8. Build Tauri Desktop → KeepContact-Iteration-Setup.exe / KeepContact-Iteration.msi
console.log('\n8. Building iteration Tauri Desktop installer...')
let hasCargo = false
try {
  execSync('cargo --version', { stdio: 'ignore' })
  hasCargo = true
} catch {}

if (hasCargo) {
  try {
    run('npm run tauri build')

    const desktopDir = join(root, 'public/desktop')
    if (!existsSync(desktopDir)) mkdirSync(desktopDir, { recursive: true })

    const builtExe = join(root, `src-tauri/target/release/bundle/nsis/Keep Contact_${versionName}_x64-setup.exe`)
    const destExe = join(desktopDir, 'KeepContact-Iteration-Setup.exe')

    const builtMsi = join(root, `src-tauri/target/release/bundle/msi/Keep Contact_${versionName}_x64_en-US.msi`)
    const destMsi = join(desktopDir, 'KeepContact-Iteration.msi')

    if (existsSync(builtExe)) {
      copyFileSync(builtExe, destExe)
      console.log(`   ✓ EXE → ${destExe}`)
    } else {
      console.warn(`   ⚠ EXE not found at: ${builtExe}`)
    }

    if (existsSync(builtMsi)) {
      copyFileSync(builtMsi, destMsi)
      console.log(`   ✓ MSI → ${destMsi}`)
    } else {
      console.warn(`   ⚠ MSI not found at: ${builtMsi}`)
    }
  } catch (err) {
    console.error('   ✗ Tauri build failed:', err.message)
  }
} else {
  console.log('   ⚠ Cargo/Rust not found. Skipping Tauri build.')
}

console.log('\n✅ Iteration release complete!')
console.log(`   Web:     ${ITERATION_URL}`)
console.log(`   APK:     public/keep-contact-iteration.apk`)
console.log(`   EXE:     public/desktop/KeepContact-Iteration-Setup.exe`)
console.log(`\n   Commit with:`)
console.log(`   git add . && git commit -m "chore(iter): release iteration v${versionName}" && git push`)
