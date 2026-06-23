// 一键发布 Android:升版本号 → 构建 Web → cap sync → 签名 APK → 传到 GitHub Release。
// 用法: npm run release:android -- <versionName>   例: npm run release:android -- 0.4.2
import { execSync } from 'node:child_process'
import { readFileSync, writeFileSync, copyFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const REPO = 'vinz-astudio/keepcontect'
const run = (cmd, opts = {}) =>
  execSync(cmd, { stdio: 'inherit', cwd: root, ...opts })

const arg = process.argv[2]
if (!arg) {
  console.error('用法: npm run release:android -- <versionName>   例: 0.4.2')
  process.exit(1)
}
const tag = arg.startsWith('v') ? arg : `v${arg}`
const versionName = tag.replace(/^v/, '')

// 1) 升 versionCode(+1)并写入 versionName,保证侧载可覆盖升级
const gradlePath = join(root, 'android/app/build.gradle')
let gradle = readFileSync(gradlePath, 'utf8')
const m = gradle.match(/versionCode\s+(\d+)/)
if (!m) throw new Error('在 build.gradle 找不到 versionCode')
const nextCode = parseInt(m[1], 10) + 1
gradle = gradle
  .replace(/versionCode\s+\d+/, `versionCode ${nextCode}`)
  .replace(/versionName\s+"[^"]*"/, `versionName "${versionName}"`)
writeFileSync(gradlePath, gradle)
console.log(`→ versionCode ${nextCode}, versionName ${versionName}`)

// 1b) 同步产品版本号:src/lib/version.ts 的 APP_VERSION 与 public/version.json
const verTsPath = join(root, 'src/lib/version.ts')
let verTs = readFileSync(verTsPath, 'utf8')
verTs = verTs.replace(/APP_VERSION\s*=\s*'[^']*'/, `APP_VERSION = '${versionName}'`)
writeFileSync(verTsPath, verTs)
const verJsonPath = join(root, 'public/version.json')
const verJson = JSON.parse(readFileSync(verJsonPath, 'utf8'))
verJson.version = versionName
writeFileSync(verJsonPath, JSON.stringify(verJson, null, 2) + '\n')
console.log(`→ APP_VERSION & version.json = ${versionName}`)

// 2) 构建 Web 产物并同步进原生工程
run('npm run build')
run('node scripts/clean-tauri-dist.js')
run('npx cap sync android')

// 3) 构建发布签名 APK(Windows 用 gradlew.bat 绝对路径,避免 shell 找不到;
//    签名密钥来自 gitignore 的 keystore.properties)
const gradlew =
  process.platform === 'win32'
    ? `"${join(root, 'android', 'gradlew.bat')}"`
    : './gradlew'
run(`${gradlew} assembleRelease --console=plain`, { cwd: join(root, 'android') })

// 4) 复制成稳定文件名 keep-contact.apk (包括复制到 public 文件夹，供 Vercel 静态分发)
const built = join(root, 'android/app/build/outputs/apk/release/app-release.apk')
const asset = join(root, 'android/app/build/outputs/apk/release/keep-contact.apk')
const publicAsset = join(root, 'public/keep-contact.apk')

copyFileSync(built, asset)
copyFileSync(built, publicAsset)
console.log(`✓ 已成功复制 APK 至: ${publicAsset}`)

// 5) 创建 GitHub Release 并标记 latest(用对该仓库有写权限的账号 token,不打印)
try {
  console.log('正在尝试推送到 GitHub Release...')
  const token = execSync(`gh auth token -u vinz-astudio`, { cwd: root })
    .toString()
    .trim()
  const notes = `Release-signed Android build. 下载 keep-contact.apk 安装即可。`
  run(
    `gh release create ${tag} "${asset}" --repo ${REPO} --title "Keep Contact ${tag} — Android" --latest --notes "${notes}"`,
    { env: { ...process.env, GH_TOKEN: token } },
  )
  console.log(`✓ 已发布 GitHub Release ${tag}`)
} catch (e) {
  console.warn('⚠️ GitHub Release 发布失败 (可能因为未安装 gh cli 或未登录)。本地 APK 构建已完成，不受影响。')
}

console.log(`\n✓ 已发布 ${tag}`)
console.log('  记得提交版本号变更: git commit -am "chore(android): release ' + tag + '"')
