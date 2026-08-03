import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.join(__dirname, '..');
const roots = [
  path.join(rootDir, 'android/app/src/main/assets/public'),
  path.join(rootDir, 'ios/App/App/public'),
];

// Installer artifacts are served from public/, but must never be bundled back
// into web assets, Android APKs, or Tauri installers.
//
// Vite copies the whole of public/ into dist/, and `cap sync` copies dist/ into
// the Android asset folder, so anything left behind here ships inside the next
// build — and then becomes part of the release that the build after that
// swallows in turn. That compounding is what took the APK from 4.6 MB (v0.5.22)
// to 73 MB (v0.5.23) to 588 MB (v0.5.25).
//
// Match by extension, recursively. The earlier version matched `.apk` by name
// and the desktop installers by one exact relative path, so it missed both the
// `.aab` bundles and the `.exe` files that sit at the root of public/ with a
// version in their filename.
//
// Wired to `postbuild` rather than called by each release script: the iOS
// TestFlight workflow ran `npm run build && npx cap sync ios` and never invoked
// this, so the whole installer pile shipped inside the iOS app. A pipeline that
// has to remember an extra step is a pipeline that will forget it.
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
