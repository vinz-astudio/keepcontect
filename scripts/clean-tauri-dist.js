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
  if (fs.existsSync(root)) {
    try {
      const files = fs.readdirSync(root);
      for (const file of files) {
        if (file.startsWith('keep-contact') && file.endsWith('.apk')) {
          const target = path.join(root, file);
          fs.unlinkSync(target);
          console.log(`[Installer Clean] Removed ${path.relative(rootDir, target)}`);
        }
      }
    } catch (err) {
      console.error(`Failed to clean APKs in ${root}:`, err);
    }
  }
  for (const rel of relativeTargets) {
    if (rel.endsWith('.apk')) continue;
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
