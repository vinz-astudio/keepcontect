// Build a GM-only canary from main, tag it, upload immutable GitHub Release assets,
// and sync Supabase app_versions.status = canary.
//
// Usage: node scripts/release-canary.mjs 0.5.17

import { execSync } from 'node:child_process'
import { copyFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const REPO = 'vinz-astudio/keepcontect'
const root = join(dirname(fileURLToPath(import.meta.url)), '..')

const run = (cmd, opts = {}) =>
  execSync(cmd, { stdio: 'inherit', cwd: root, ...opts })
const read = (cmd) => execSync(cmd, { cwd: root, encoding: 'utf8' }).trim()
const commandOk = (cmd) => {
  try {
    execSync(cmd, { cwd: root, stdio: 'ignore' })
    return true
  } catch {
    return false
  }
}

function requireMainAndClean() {
  const branch = read('git branch --show-current')
  if (branch !== 'main') {
    throw new Error(`Canary releases must run from main, current branch is ${branch || '(detached)'}.`)
  }
  const status = read('git status --porcelain')
  if (status) {
    throw new Error('Worktree must be clean before release:canary. Commit intended changes first.')
  }
}

function requireTauriSigningKey() {
  if (!process.env.TAURI_SIGNING_PRIVATE_KEY) {
    throw new Error('TAURI_SIGNING_PRIVATE_KEY is required for Tauri desktop canary. Set it in local env or skip desktop by running Android-only release tooling.')
  }
}

function bumpVersions(versionName, apkUrl, exeUrl) {
  const verTsPath = join(root, 'src/lib/version.ts')
  let verTs = readFileSync(verTsPath, 'utf8')
  verTs = verTs.replace(/APP_VERSION\s*=\s*'[^']*'/, `APP_VERSION = '${versionName}'`)
  writeFileSync(verTsPath, verTs)

  const verJsonPath = join(root, 'public/version.json')
  const verJson = JSON.parse(readFileSync(verJsonPath, 'utf8'))
  verJson.version = versionName
  verJson.apkUrl = apkUrl
  verJson.exeUrl = exeUrl
  writeFileSync(verJsonPath, JSON.stringify(verJson, null, 2) + '\n')

  const tauriConfPath = join(root, 'src-tauri/tauri.conf.json')
  if (existsSync(tauriConfPath)) {
    const tauriConf = JSON.parse(readFileSync(tauriConfPath, 'utf8'))
    tauriConf.version = versionName
    writeFileSync(tauriConfPath, JSON.stringify(tauriConf, null, 2) + '\n')
  }

  const cargoTomlPath = join(root, 'src-tauri/Cargo.toml')
  if (existsSync(cargoTomlPath)) {
    let cargoToml = readFileSync(cargoTomlPath, 'utf8')
    cargoToml = cargoToml.replace(/^version\s*=\s*"[^"]*"/m, `version = "${versionName}"`)
    writeFileSync(cargoTomlPath, cargoToml)
  }

  const gradlePath = join(root, 'android/app/build.gradle')
  if (existsSync(gradlePath)) {
    let gradle = readFileSync(gradlePath, 'utf8')
    const match = gradle.match(/versionCode\s+(\d+)/)
    if (!match) throw new Error('Could not parse Android versionCode.')
    const nextCode = parseInt(match[1], 10) + 1
    gradle = gradle
      .replace(/versionCode\s+\d+/, `versionCode ${nextCode}`)
      .replace(/versionName\s+"[^"]*"/, `versionName "${versionName}"`)
    writeFileSync(gradlePath, gradle)
  }
}

function commitVersionBump(versionName) {
  const files = [
    'src/lib/version.ts',
    'public/version.json',
    'android/app/build.gradle',
    'src-tauri/tauri.conf.json',
    'src-tauri/Cargo.toml',
  ].filter((rel) => existsSync(join(root, rel)))

  run(`git add ${files.map((file) => `"${file}"`).join(' ')}`)
  if (!commandOk('git diff --cached --quiet')) {
    run(`git commit -m "chore(canary): prepare v${versionName}"`)
  }
}

function ensureTag(tag, versionName) {
  const exists = commandOk(`git rev-parse -q --verify refs/tags/${tag}`)
  if (!exists) run(`git tag -a ${tag} -m "Keep Contact ${tag}"`)
  run(`git push origin refs/tags/${tag}`)
  console.log(`   - tag pushed: ${tag}`)
}

function uploadRelease(tag, versionName, assets) {
  const existing = commandOk(`gh release view ${tag} --repo ${REPO}`)
  const quotedAssets = assets.map((asset) => `"${asset}"`).join(' ')
  if (existing) {
    run(`gh release upload ${tag} ${quotedAssets} --repo ${REPO} --clobber`)
    run(`gh release edit ${tag} --repo ${REPO} --prerelease --title "Keep Contact ${tag} — Canary"`)
  } else {
    run(`gh release create ${tag} ${quotedAssets} --repo ${REPO} --prerelease --latest=false --title "Keep Contact ${tag} — Canary" --notes "GM canary build. Promote through Supabase app_versions after verification."`)
  }
}

const arg = process.argv[2]
if (!arg) {
  console.error('Usage: node scripts/release-canary.mjs <versionName>   Example: 0.5.17')
  process.exit(1)
}

const tag = arg.startsWith('v') ? arg : `v${arg}`
const versionName = tag.replace(/^v/, '')
const apkAssetName = `keep-contact-${versionName}.apk`
const exeAssetName = `KeepContact-${versionName}-Setup.exe`
const apkUrl = `https://github.com/${REPO}/releases/download/${tag}/${apkAssetName}`
const exeUrl = `https://github.com/${REPO}/releases/download/${tag}/${exeAssetName}`
const releaseDir = join(root, 'dist', 'release-assets', tag)

console.log(`\nKeep Contact canary release: ${tag}\n`)

requireMainAndClean()
bumpVersions(versionName, apkUrl, exeUrl)
commitVersionBump(versionName)

console.log('\nBuilding Web application...')
run('npm run build')
run('node scripts/clean-tauri-dist.js')

mkdirSync(releaseDir, { recursive: true })
const assets = []

console.log('\nBuilding Android APK...')
run('npx cap sync android')
const gradlewPath = join(root, 'android', process.platform === 'win32' ? 'gradlew.bat' : 'gradlew')
const gradlew = process.platform === 'win32' ? `"${gradlewPath}"` : './gradlew'
run(`${gradlew} assembleRelease --console=plain`, { cwd: join(root, 'android') })
const builtApk = join(root, 'android/app/build/outputs/apk/release/app-release.apk')
if (!existsSync(builtApk)) throw new Error(`Built APK not found: ${builtApk}`)
const apkAsset = join(releaseDir, apkAssetName)
copyFileSync(builtApk, apkAsset)
assets.push(apkAsset)

console.log('\nBuilding Tauri desktop installer...')
try {
  execSync('cargo --version', { stdio: 'ignore' })
  requireTauriSigningKey()
  run('npm run tauri build')
  const builtExe = join(root, `src-tauri/target/release/bundle/nsis/Keep Contact_${versionName}_x64-setup.exe`)
  if (existsSync(builtExe)) {
    const exeAsset = join(releaseDir, exeAssetName)
    copyFileSync(builtExe, exeAsset)
    assets.push(exeAsset)
  } else {
    console.warn(`   ! Desktop EXE not found: ${builtExe}`)
  }
} catch (error) {
  console.warn(`   ! Desktop canary skipped: ${error instanceof Error ? error.message : String(error)}`)
}

ensureTag(tag, versionName)
uploadRelease(tag, versionName, assets)
const uploadedExeUrl = assets.some((asset) => asset.endsWith(exeAssetName)) ? exeUrl : ''
run(`node scripts/sync-app-version.mjs canary ${versionName} ${apkUrl} ${uploadedExeUrl}`)

console.log(`\nCanary ready: ${tag}`)
console.log('GM channel: canary')
console.log(`APK: ${apkUrl}`)
if (uploadedExeUrl) console.log(`EXE: ${uploadedExeUrl}`)
