import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const distDir = path.join(__dirname, '../dist');

// List of installer files we want to delete from the dist folder before Tauri bundles it.
const targets = [
  path.join(distDir, 'keep-contact.apk'),
  path.join(distDir, 'desktop/KeepContact-Setup.exe'),
  path.join(distDir, 'desktop/KeepContact.msi')
];

for (const target of targets) {
  if (fs.existsSync(target)) {
    try {
      fs.unlinkSync(target);
      console.log(`[Tauri Pre-Build] Removed installer: ${path.basename(target)}`);
    } catch (err) {
      console.error(`Failed to delete ${target}:`, err);
    }
  }
}
