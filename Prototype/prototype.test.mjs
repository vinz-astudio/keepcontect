import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const html = readFileSync(join(here, 'interactive_prototype.html'), 'utf8');
const setup = html.match(/<dialog id="setup-dialog"[\s\S]*?<\/dialog>/)?.[0] ?? '';
const deviceFrame = html.slice(html.indexOf('<div class="device-frame"'), html.indexOf('<dialog id="setup-dialog"'));

const checks = [
  ['uses the current four-destination navigation', () => {
    for (const label of ['Watch', 'Routine', 'Circles', 'Me']) {
      assert.match(html, new RegExp(`>${label}<`));
    }
  }],
  ['opens with a user benefit instead of a persona question', () => {
    assert.match(setup, /Stay connected without checking in all day/);
    assert.match(setup, /quietly checks for everyday signs/i);
    assert.match(setup, /Set up this phone/);
    assert.doesNotMatch(setup, /How do you use Keep Contact\?|data-role=/);
  }],
  ['contains two user tasks followed by an honest setup result', () => {
    assert.match(setup, /data-setup-step="1"/);
    assert.match(setup, /data-setup-step="2"/);
    assert.match(setup, /data-setup-step="3"/);
    assert.match(setup, /Step 1 of 2/);
    assert.match(setup, /This phone is ready/);
    assert.match(setup, /Protection is limited/);
    assert.match(setup, /Go to Home/);
  }],
  ['keeps device and scenario selection out of user onboarding', () => {
    assert.doesNotMatch(setup, /data-platform=|data-debug-platform=|<select/i);
    assert.match(html, /data-debug-platform="android-native"/);
    assert.match(html, /data-debug-platform="ios-native"/);
    assert.match(html, /data-debug-platform="ios-pwa"/);
    assert.doesNotMatch(deviceFrame, /data-debug-platform=/);
  }],
  ['uses plain-language phone setup copy', () => {
    for (const label of ['Notifications', 'Phone activity', 'Background protection']) {
      assert.match(setup, new RegExp(label, 'i'));
    }
    for (const internalTerm of ['Usage Access', 'Native Guard', 'push token', 'verification baseline']) {
      assert.doesNotMatch(setup, new RegExp(internalTerm, 'i'));
    }
  }],
  ['keeps safety-pattern setup outside onboarding', () => {
    assert.doesNotMatch(setup, /Practice your safety check-in|data-pattern-part=/i);
    assert.match(html, /data-action="(?:practice-pattern|change-pattern)"/);
    assert.match(html, /Safety check-in setup/);
  }],
  ['implements automatic readiness and limited-state behavior', () => {
    for (const name of ['renderPermissionList', 'runAutomaticCheck', 'renderSetupResult', 'completeSetup']) {
      assert.match(html, new RegExp(`function\\s+${name}\\s*\\(`));
    }
    assert.match(html, /Continue with limited protection/);
    assert.match(html, /readinessState === 'limited'/);
  }],
  ['uses semantic accessible controls', () => {
    assert.match(html, /aria-valuenow="0"/);
    assert.match(html, /aria-expanded="false"/);
    assert.match(html, /aria-current="page"/);
    assert.match(html, /aria-modal="true"/);
    assert.match(html, /role="dialog"/);
    assert.match(html, /:focus-visible/);
    assert.doesNotMatch(html, /\son(?:click|mousedown|mouseup|touchstart|touchend)=/i);
  }],
  ['masks emergency location details by default', () => {
    assert.match(html, /data-action="reveal-location"/);
    assert.match(html, /Home address hidden/);
    assert.doesNotMatch(html, /37\.7749|-122\.4194/);
  }],
  ['has parseable inline JavaScript and unique element ids', () => {
    const scripts = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map((match) => match[1]);
    assert.equal(scripts.length, 1);
    for (const source of scripts) Function(source);
    const ids = [...html.matchAll(/\sid="([^"]+)"/g)].map((match) => match[1]);
    const duplicateIds = [...new Set(ids.filter((id, index) => ids.indexOf(id) !== index))];
    assert.deepEqual(duplicateIds, []);
    assert.equal((html.match(/<dialog\b/g) || []).length, (html.match(/<\/dialog>/g) || []).length);
  }]
];

const failures = [];
for (const [name, check] of checks) {
  try {
    check();
    console.log(`PASS ${name}`);
  } catch (error) {
    failures.push(`${name}: ${error.message}`);
    console.error(`FAIL ${name}`);
  }
}

if (failures.length) {
  console.error(`\n${failures.length} prototype contract check(s) failed:`);
  for (const failure of failures) console.error(`- ${failure}`);
  process.exitCode = 1;
} else {
  console.log(`\nPASS all ${checks.length} prototype contract checks`);
}
