// Promote an already-tagged canary to the released channel.
//
// Usage: node scripts/promote-release.mjs 0.5.17

import { execSync } from 'node:child_process'
import { dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const REPO = 'vinz-astudio/keepcontect'
const root = dirname(fileURLToPath(new URL('../package.json', import.meta.url)))

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

const arg = process.argv[2]
if (!arg) {
  console.error('Usage: node scripts/promote-release.mjs <versionName>   Example: 0.5.17')
  process.exit(1)
}

const tag = arg.startsWith('v') ? arg : `v${arg}`
const versionName = tag.replace(/^v/, '')
const apkAssetName = `keep-contact-${versionName}.apk`
const exeAssetName = `KeepContact-${versionName}-Setup.exe`
const apkUrl = `https://github.com/${REPO}/releases/download/${tag}/${apkAssetName}`
const exeUrl = `https://github.com/${REPO}/releases/download/${tag}/${exeAssetName}`

if (!commandOk(`git rev-parse -q --verify refs/tags/${tag}`)) {
  throw new Error(`Local tag not found: ${tag}. Fetch tags or run release:canary first.`)
}

const branch = read('git branch --show-current')
const head = read('git rev-parse HEAD')
const tagCommit = read(`git rev-list -n 1 ${tag}`)
if (branch === 'main' && head === tagCommit) {
  run('git push origin main')
} else {
  console.warn(`   ! main not pushed automatically. Current branch/head is not ${tag}.`)
  console.warn('   ! If this release should update production Web/PWA, checkout main at the tag and push main.')
}

if (commandOk(`gh release view ${tag} --repo ${REPO}`)) {
  run(`gh release edit ${tag} --repo ${REPO} --prerelease=false --latest --title "Keep Contact ${tag} — Released"`)
} else {
  console.warn(`   ! GitHub release ${tag} not found. Supabase will still be updated.`)
}

run(`node scripts/sync-app-version.mjs released ${versionName} ${apkUrl} ${exeUrl}`)

console.log(`\nReleased channel promoted: ${tag}`)
console.log(`APK: ${apkUrl}`)
console.log(`EXE: ${exeUrl}`)
