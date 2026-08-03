// 安全网:原生 app bundle 里不许出现安装包,发现就让构建失败。
//
// 结构上安装包已经搬出 public/,原生流水线本来就看不到它们(见
// release-artifacts/README.md)。本脚本存在是因为**上一版的做法失败过**:
// 当时靠每条流水线各自记得调用清理脚本,结果 5 个调用点里 3 个是错的 ——
// release.mjs 与 release-canary.mjs 把清理放在了 cap sync 之前(清的是上一次
// 的残留),iOS 的 CI 则根本没接。代价是一个真实内容 1.2 MB 的 App 以 120 MB
// 上传 TestFlight,以及一个正常 4.7 MB 的 APK 打成了 167 MB。
//
// 所以这一层不做清理,只做断言。清理是"悄悄修好然后继续",断言是"当场喊停" ——
// 对一个已经悄悄坏过三次的问题,后者才是对的。

import { existsSync, readdirSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const rootDir = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');

// dist/ 不在列表里:构建网页时那里**应该**有安装包。只检查会被打进原生包的地方。
const NATIVE_BUNDLE_DIRS = [
  'android/app/src/main/assets/public',
  'ios/App/App/public',
];

const INSTALLER_EXTENSIONS = ['.apk', '.aab', '.exe', '.msi'];

function findInstallers(dir, found = []) {
  let entries;
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return found;
  }
  for (const entry of entries) {
    const target = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      findInstallers(target, found);
      continue;
    }
    if (INSTALLER_EXTENSIONS.some((ext) => entry.name.toLowerCase().endsWith(ext))) {
      found.push({ file: path.relative(rootDir, target), size: statSync(target).size });
    }
  }
  return found;
}

const offenders = [];
for (const relative of NATIVE_BUNDLE_DIRS) {
  const dir = path.join(rootDir, relative);
  if (!existsSync(dir)) continue;
  offenders.push(...findInstallers(dir));
}

if (offenders.length > 0) {
  const total = offenders.reduce((sum, o) => sum + o.size, 0);
  console.error('\n[Installer Guard] 原生 app bundle 里混进了安装包,构建中止:\n');
  for (const o of offenders) {
    console.error(`  ${(o.size / 1048576).toFixed(1).padStart(7)} MB  ${o.file}`);
  }
  console.error(`\n  合计 ${(total / 1048576).toFixed(1)} MB 会被打进这个包。`);
  console.error('\n  多半是有安装包被放回了 public/。安装包应放在 release-artifacts/,');
  console.error('  它只在 `npm run build:web` 时才进 dist/。见 release-artifacts/README.md。\n');
  process.exit(1);
}

console.log('[Installer Guard] 原生 bundle 干净,未发现安装包');
