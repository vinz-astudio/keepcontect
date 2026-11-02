import { describe, it, expect } from 'vitest';
import { usesAlertPush } from './alertPushKinds';

describe('alertPushKinds', () => {
  it('displays the kinds addressed to the subject themselves', () => {
    expect(usesAlertPush('concern')).toBe(true);
    expect(usesAlertPush('self')).toBe(true);
  });

  // The self-test checks that a locked phone shows a notification. On iOS a
  // tickle only displays while the app is alive, so a test sent as a tickle
  // could fail and tell the user push is broken when it is not. Its text names
  // no one, so it is safe in a payload Apple can read.
  it('displays the self-test notification', () => {
    expect(usesAlertPush('test')).toBe(true);
  });

  it('keeps every escalation kind on the content-free tickle', () => {
    // These name a third party and describe their jeopardy, so their text must
    // never reach a payload Apple or Google can read.
    for (const kind of ['group', 'community', 'terminal']) {
      expect(usesAlertPush(kind)).toBe(false);
    }
  });

  it('keeps unrelated kinds on the tickle by default', () => {
    for (const kind of ['on_it', 'resolved', 'task_invite', 'task_due', '']) {
      expect(usesAlertPush(kind)).toBe(false);
    }
  });
});
