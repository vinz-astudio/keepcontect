// scripts/release.mjs
// A unified release script to bump versions, build web, compile Android APK, compile Tauri desktop apps, and copy binaries.
// Usage: node scripts/release.mjs <versionName>  Example: node scripts/release.mjs 0.4.4

import { execSync } from 'node:child_process'
import { readFileSync, writeFileSync, copyFileSync, existsSync, mkdirSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const run = (cmd, opts = {}) =>
  execSync(cmd, { stdio: 'inherit', cwd: root, ...opts })

const arg = process.argv[2]
if (!arg) {
  console.error('Usage: node scripts/release.mjs <versionName>   Example: 0.4.4')
  process.exit(1)
}
const tag = arg.startsWith('v') ? arg : `v${arg}`
const versionName = tag.replace(/^v/, '')

console.log(`Starting Keep Contact Release Process for version: ${versionName}\n`)

// 1. Bump version in src/lib/version.ts
console.log('1. Bumping version in src/lib/version.ts...')
const verTsPath = join(root, 'src/lib/version.ts')
if (existsSync(verTsPath)) {
  let verTs = readFileSync(verTsPath, 'utf8')
  verTs = verTs.replace(/APP_VERSION\s*=\s*'[^']*'/, `APP_VERSION = '${versionName}'`)
  writeFileSync(verTsPath, verTs)
  console.log(`   - Updated APP_VERSION = '${versionName}'`)
} else {
  console.warn('   - Warn: src/lib/version.ts not found!')
}

// 2. Bump version in public/version.json
console.log('2. Bumping version in public/version.json...')
const verJsonPath = join(root, 'public/version.json')
if (existsSync(verJsonPath)) {
  const verJson = JSON.parse(readFileSync(verJsonPath, 'utf8'))
  verJson.version = versionName
  writeFileSync(verJsonPath, JSON.stringify(verJson, null, 2) + '\n')
  console.log(`   - Updated version = '${versionName}'`)
} else {
  console.warn('   - Warn: public/version.json not found!')
}

// 3. Bump version in src-tauri/tauri.conf.json
console.log('3. Bumping version in src-tauri/tauri.conf.json...')
const tauriConfPath = join(root, 'src-tauri/tauri.conf.json')
if (existsSync(tauriConfPath)) {
  const tauriConf = JSON.parse(readFileSync(tauriConfPath, 'utf8'))
  tauriConf.version = versionName
  writeFileSync(tauriConfPath, JSON.stringify(tauriConf, null, 2) + '\n')
  console.log(`   - Updated tauri.conf.json version = '${versionName}'`)
} else {
  console.warn('   - Warn: src-tauri/tauri.conf.json not found!')
}

// 4. Bump version in src-tauri/Cargo.toml
console.log('4. Bumping version in src-tauri/Cargo.toml...')
const cargoTomlPath = join(root, 'src-tauri/Cargo.toml')
if (existsSync(cargoTomlPath)) {
  let cargoToml = readFileSync(cargoTomlPath, 'utf8')
  cargoToml = cargoToml.replace(/^version\s*=\s*"[^"]*"/m, `version = "${versionName}"`)
  writeFileSync(cargoTomlPath, cargoToml)
  console.log(`   - Updated Cargo.toml version = "${versionName}"`)
} else {
  console.warn('   - Warn: src-tauri/Cargo.toml not found!')
}

// 5. Bump version in android/app/build.gradle
console.log('5. Bumping version in android/app/build.gradle...')
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
    console.log(`   - Updated versionCode to ${nextCode}, versionName to "${versionName}"`)
  } else {
    console.warn('   - Warn: Could not parse versionCode from build.gradle!')
  }
} else {
  console.warn('   - Warn: android/app/build.gradle not found!')
}

// 6. Build Web app
console.log('\n6. Building Web application...')
run('npm run build')
run('node scripts/clean-tauri-dist.js')

// 7. Sync and Build Android APK
console.log('\n7. Syncing and building Android APK...')
const gradlewPath = join(root, 'android', process.platform === 'win32' ? 'gradlew.bat' : 'gradlew')
if (existsSync(gradlewPath)) {
  try {
    run('npx cap sync android')
    const gradlew = process.platform === 'win32' ? `"${gradlewPath}"` : './gradlew'
    run(`${gradlew} assembleRelease --console=plain`, { cwd: join(root, 'android') })
    
    // Copy output APK
    const builtApk = join(root, 'android/app/build/outputs/apk/release/app-release.apk')
    const destApk = join(root, 'public/keep-contact.apk')
    if (existsSync(builtApk)) {
      copyFileSync(builtApk, destApk)
      console.log(`   - Successfully copied APK to: ${destApk}`)
    } else {
      console.warn('   - Warn: Built APK not found at target path!')
    }
  } catch (err) {
    console.error('   - Error building Android APK:', err.message)
  }
} else {
  console.log('   - Gradlew not found. Skipping Android build.')
}

// 8. Build Tauri Desktop Installer
console.log('\n8. Checking Tauri Desktop build prerequisites...')
let hasCargo = false
try {
  execSync('cargo --version', { stdio: 'ignore' })
  hasCargo = true
} catch {}

if (hasCargo) {
  console.log('   - Cargo/Rust toolchain found! Building Tauri App...')
  try {
    run('npm run tauri build')
    
    // Copy and rename output installers
    const desktopDir = join(root, 'public/desktop')
    if (!existsSync(desktopDir)) {
      mkdirSync(desktopDir, { recursive: true })
    }
    
    // Format target file names: Keep Contact_<version>_x64-setup.exe
    const builtExe = join(root, `src-tauri/target/release/bundle/nsis/Keep Contact_${versionName}_x64-setup.exe`)
    const destExe = join(desktopDir, 'KeepContact-Setup.exe')
    
    const builtMsi = join(root, `src-tauri/target/release/bundle/msi/Keep Contact_${versionName}_x64_en-US.msi`)
    const destMsi = join(desktopDir, 'KeepContact.msi')
    
    if (existsSync(builtExe)) {
      copyFileSync(builtExe, destExe)
      console.log(`   - Successfully copied EXE to: ${destExe}`)
    } else {
      console.warn(`   - Warn: Built EXE not found at: ${builtExe}`)
    }
    
    if (existsSync(builtMsi)) {
      copyFileSync(builtMsi, destMsi)
      console.log(`   - Successfully copied MSI to: ${destMsi}`)
    } else {
      console.warn(`   - Warn: Built MSI not found at: ${builtMsi}`)
    }
  } catch (err) {
    console.error('   - Error building Tauri Desktop App:', err.message)
  }
} else {
  console.log('   - ⚠️ Cargo/Rust not found in PATH. Skipping Tauri desktop build.')
  console.log('     Please run the build on a machine with Rust installed, or compile manually.')
}

console.log('\n✓ Release process completed!')
console.log(`  To commit changes, run:`)
console.log(`  git commit -am "chore(release): bump version to ${versionName} and compile binaries"`)
