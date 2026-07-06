import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.join(__dirname, '..');
const roots = [
  path.join(rootDir, 'dist'),
  path.join(rootDir, 'android/app/src/main/assets/public'),
];

// Installer artifacts are served from public/, but must never be bundled back
// into web assets, Android APKs, or Tauri installers.
const relativeTargets = [
  'keep-contact.apk',
  'desktop/KeepContact-Setup.exe',
  'desktop/KeepContact.msi',
];

for (const root of roots) {
  for (const rel of relativeTargets) {
    const target = path.join(root, rel);
    if (fs.existsSync(target)) {
      try {
        fs.unlinkSync(target);
        console.log(`[Installer Clean] Removed ${path.relative(rootDir, target)}`);
      } catch (err) {
        console.error(`Failed to delete ${target}:`, err);
      }
    }
  }
}
