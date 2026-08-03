import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.join(__dirname, '..');
const roots = [
  path.join(rootDir, 'android/app/src/main/assets/public'),
  path.join(rootDir, 'ios/App/App/public'),
];

const INSTALLER_EXTENSIONS = ['.apk', '.aab', '.exe', '.msi'];

function cleanTree(dir) {
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return;
  }
  for (const entry of entries) {
    const target = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      cleanTree(target);
      continue;
    }
    if (!INSTALLER_EXTENSIONS.some((ext) => entry.name.toLowerCase().endsWith(ext))) continue;
    try {
      fs.unlinkSync(target);
      console.log(`[Installer Clean] Removed ${path.relative(rootDir, target)}`);
    } catch (err) {
      console.error(`Failed to delete ${target}:`, err);
    }
  }
}

for (const root of roots) {
  if (fs.existsSync(root)) cleanTree(root);
}
