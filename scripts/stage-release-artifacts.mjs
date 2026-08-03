// 把 release-artifacts/ 拷进 dist/,只在构建**网页**时跑。
//
// 安装包不放在 public/,因为 Vite 会把 public/ 原样拷进 dist/,而 `cap sync`
// 又把 dist/ 原样拷进原生 app bundle —— 安装包会因此被打进 APK 和 IPA。详见
// release-artifacts/README.md。
//
// 于是分成两条路:`npm run build` 出的是纯网页(原生流水线用),
// `npm run build:web` 才会额外跑本脚本(只有 Vercel 用)。默认安全,
// 想带上安装包必须显式选择。

import { cpSync, existsSync, readdirSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const rootDir = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const source = path.join(rootDir, 'release-artifacts');
const target = path.join(rootDir, 'dist');

if (!existsSync(source)) {
  console.log('[Stage Artifacts] release-artifacts/ 不存在,跳过');
  process.exit(0);
}

if (!existsSync(target)) {
  // 先跑 vite build 才有 dist/。这里失败通常意味着命令顺序反了。
  console.error('[Stage Artifacts] dist/ 不存在 —— 本脚本必须在 vite build 之后运行');
  process.exit(1);
}

let staged = 0;
let bytes = 0;

for (const entry of readdirSync(source, { withFileTypes: true })) {
  // README 是给人看的规则说明,不该上线。
  if (entry.name === 'README.md') continue;
  const from = path.join(source, entry.name);
  const to = path.join(target, entry.name);
  cpSync(from, to, { recursive: true });
  if (entry.isDirectory()) {
    for (const inner of readdirSync(from, { withFileTypes: true })) {
      if (inner.isFile()) {
        bytes += statSync(path.join(from, inner.name)).size;
        staged += 1;
      }
    }
  } else {
    bytes += statSync(from).size;
    staged += 1;
  }
  console.log(`[Stage Artifacts] ${entry.name} → dist/`);
}

console.log(`[Stage Artifacts] 已上线 ${staged} 个文件,共 ${(bytes / 1048576).toFixed(1)} MB`);
