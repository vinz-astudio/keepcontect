import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const html = readFileSync(join(here, 'interactive_prototype.html'), 'utf8');
const setup = html.match(/<dialog id="setup-dialog"[\s\S]*?<\/dialog>/)?.[0] ?? '';
const deviceFrame = html.slice(html.indexOf('<div class="device-frame"'), html.indexOf('<dialog id="setup-dialog"'));
const watchSurface = html.slice(html.indexOf('<section class="screen" id="watch"'), html.indexOf('<section class="card" id="activity-history"'));
const alertResponse = watchSurface.match(/<section class="alert-response"[\s\S]*?<\/section>/)?.[0] ?? '';
const watchWithoutAlert = watchSurface.replace(alertResponse, '');

function personSurface(id) {
  return watchSurface.match(new RegExp(`<article class="person-card" id="${id}"[\\s\\S]*?<\\/article>`))?.[0] ?? '';
}

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
  ['keeps Watch summary, own task, people and history in approved order', () => {
    const ids = ['watch-action-summary', 'watch-own-checkin', 'watch-people-list', 'activity-history'];
    const positions = ids.map((id) => html.indexOf(`id="${id}"`));
    assert.ok(positions.every((position) => position >= 0));
    assert.deepEqual([...positions].sort((a, b) => a - b), positions);
    assert.doesNotMatch(html, /id="checkin-tasks"/);
  }],
  ['gives each collapsed watched person decision context', () => {
    const people = [...html.matchAll(/<article class="person-card[\s\S]*?<\/article>/g)].map((match) => match[0]);
    assert.ok(people.length >= 3);
    for (const person of people) {
      for (const token of ['data-relationship', 'data-circle', 'data-evidence-source', 'data-coverage']) {
        assert.match(person, new RegExp(token));
      }
      assert.match(person, /data-action="toggle-person"/);
    }
  }],
  ['keeps scheduled check-ins inside Guardian-to-Ward responsibility', () => {
    const collapsedActions = [...watchSurface.matchAll(/<div class="person-actions">([\s\S]*?)<\/div>/g)].map((match) => match[1]);
    assert.ok(collapsedActions.length >= 3);
    for (const actions of collapsedActions) {
      assert.doesNotMatch(actions, /data-action="(?:send-concern|ask-checkin)"/);
    }

    for (const id of ['person-min', 'person-john']) {
      const person = personSurface(id);
      assert.ok(person, `${id} must exist`);
      assert.doesNotMatch(person, /data-responsibility="ward"|Check-in arrangement|data-action="(?:ask-checkin|add-checkin-task|edit-checkin-task|remove-checkin-task|send-concern)"/i);
    }

    const ward = personSurface('person-mei');
    assert.match(ward, /data-responsibility="ward"/);
    assert.match(ward, /Check-in arrangement/);
    for (const action of ['add-checkin-task', 'edit-checkin-task', 'remove-checkin-task']) {
      assert.match(ward, new RegExp(`data-action="${action}"`));
    }

    assert.match(watchSurface, /id="watch-own-checkin"[^>]*hidden/);
    assert.match(watchSurface, /data-action="complete-own-checkin"[^>]*>Check in</);
    assert.doesNotMatch(watchSurface, /data-action="ask-checkin"|Ask .* to check in/i);
  }],
  ['conditions concern and response actions on active alert state', () => {
    assert.doesNotMatch(watchWithoutAlert, /data-action="send-concern"|>Send concern</i);
    for (const action of ['send-concern', 'claim-alert', 'confirm-safe']) {
      assert.match(alertResponse, new RegExp(`data-action="${action}"`));
    }
    assert.match(html, /only available because an alert is active/i);
    assert.match(html, /Concern sent · waiting for Min to confirm/i);
    assert.match(html, /delivery and self-confirmation remain unknown/i);
    for (const scenario of ['task', 'concern-sent', 'claimed', 'resolved']) {
      assert.match(html, new RegExp(`data-watch-scenario="${scenario}"`));
    }

    const stateFunction = html.match(/function getWatchActionState\([\s\S]*?\n    \}/)?.[0] ?? '';
    assert.ok(stateFunction);
    const getWatchActionState = Function(`${stateFunction}; return getWatchActionState;`)();
    assert.deepEqual(getWatchActionState('normal'), { alertVisible: false, concernVisible: false, claimVisible: false, confirmVisible: false, ownTaskVisible: false });
    assert.deepEqual(getWatchActionState('task'), { alertVisible: false, concernVisible: false, claimVisible: false, confirmVisible: false, ownTaskVisible: true });
    assert.deepEqual(getWatchActionState('alert'), { alertVisible: true, concernVisible: true, claimVisible: true, confirmVisible: false, ownTaskVisible: false });
    assert.deepEqual(getWatchActionState('concern-sent'), { alertVisible: true, concernVisible: false, claimVisible: true, confirmVisible: false, ownTaskVisible: false });
    assert.deepEqual(getWatchActionState('claimed'), { alertVisible: true, concernVisible: false, claimVisible: false, confirmVisible: true, ownTaskVisible: false });
    assert.deepEqual(getWatchActionState('resolved'), { alertVisible: false, concernVisible: false, claimVisible: false, confirmVisible: false, ownTaskVisible: false });
  }],
  ['exposes truthful Watch scenarios outside the phone frame', () => {
    for (const scenario of ['normal', 'task', 'limited', 'alert', 'concern-sent', 'claimed', 'resolved', 'loading', 'error']) {
      assert.match(html, new RegExp(`data-watch-scenario="${scenario}"`));
    }
    assert.doesNotMatch(html, /Everything looks safe and sound/i);
    assert.match(html, /No active alerts right now/);
    assert.match(html, /Coverage limited|coverage is limited/i);
  }],
  ['retains production relationship and account destinations', () => {
    for (const action of [
      'create-circle', 'rename-circle', 'move-circle', 'share-circle', 'show-circle-qr',
      'scan-circle-qr', 'toggle-monitoring', 'toggle-sharing', 'manage-guardians',
      'scan-sync', 'sign-out', 'repair-push', 'check-update', 'clear-pattern'
    ]) assert.match(html, new RegExp(`data-action="${action}"`));
    assert.match(html, /Guardian|Ward|Responsibilities/);
    assert.match(html, /Linked devices/);
    assert.match(html, /Current version/);
  }],
  ['exposes truthful invitation handoff outcomes', () => {
    for (const result of ['accepted', 'invalid', 'already-member', 'handoff-failed']) {
      assert.match(html, new RegExp(`data-invite-result="${result}"`));
    }
    assert.doesNotMatch(html, /invitation (?:link |code )?(?:expires|will expire)/i);
  }],
  ['models routine failure and capability-specific readiness', () => {
    assert.match(html, /data-routine-result="success"/);
    assert.match(html, /data-routine-result="failure"/);
    for (const state of ['Ready', 'Limited', 'Needs action', 'Unknown']) assert.match(html, new RegExp(state));
  }],
  ['matches production SOS timing and never fabricates acknowledgement', () => {
    assert.match(html, /const SOS_HOLD_MS = 1400/);
    assert.match(html, /data-sos-result="accepted"/);
    assert.match(html, /data-sos-result="degraded"/);
    assert.match(html, /data-sos-result="failed"/);
    assert.doesNotMatch(html, /Min acknowledged your SOS/);
    assert.match(html, /Demo/);
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
  ['manages emergency contacts and saved addresses as separate cards', () => {
    for (const id of ['emergency-contacts-list', 'emergency-addresses-list', 'emergency-item-dialog']) {
      assert.match(html, new RegExp(`id="${id}"`));
    }
    for (const action of [
      'add-emergency-contact', 'edit-emergency-contact', 'remove-emergency-contact',
      'add-emergency-address', 'edit-emergency-address', 'remove-emergency-address',
      'toggle-emergency-address'
    ]) assert.match(html, new RegExp(`data-action="${action}"`));
    for (const name of ['renderEmergencyContacts', 'renderEmergencyAddresses', 'openEmergencyItemDialog', 'saveEmergencyItem', 'requestEmergencyRemoval']) {
      assert.match(html, new RegExp(`function\\s+${name}\\s*\\(`));
    }
    assert.match(html, /Primary/);
    assert.match(html, /Static reference address/);
  }],
  ['keeps device GPS behind one purpose-limited current-device consent', () => {
    assert.match(html, /id="allow-emergency-gps"/);
    assert.match(html, /current device/i);
    assert.match(html, /active crisis/i);
    assert.match(html, /does not grant (?:the )?phone location permission/i);
    assert.doesNotMatch(html, /id="device-last-locations"|Last GPS|last device locations/i);
    assert.doesNotMatch(html, /37\.7749|-122\.4194/);
  }],
  ['reserves destructive emphasis for destructive confirmations', () => {
    assert.match(html, /const destructiveActions = new Set\(\[[\s\S]*?'leave'[\s\S]*?'delete'[\s\S]*?'sign-out'[\s\S]*?'clear-pattern'/);
    assert.match(html, /destructiveActions\.has\(action\) \? 'danger' : 'accent'/);
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
