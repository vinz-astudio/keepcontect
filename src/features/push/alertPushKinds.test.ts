import { describe, it, expect } from 'vitest';
import { usesAlertPush } from './alertPushKinds';

describe('alertPushKinds', () => {
  it('displays the kinds addressed to the subject themselves', () => {
    expect(usesAlertPush('concern')).toBe(true);
    expect(usesAlertPush('self')).toBe(true);
  });

  it('keeps every escalation kind on the content-free tickle', () => {
    // These name a third party and describe their jeopardy, so their text must
    // never reach a payload Apple or Google can read.
    for (const kind of ['group', 'community', 'terminal']) {
      expect(usesAlertPush(kind)).toBe(false);
    }
  });

  it('keeps unrelated kinds on the tickle by default', () => {
    for (const kind of ['on_it', 'resolved', 'task_invite', 'task_due', 'test', '']) {
      expect(usesAlertPush(kind)).toBe(false);
    }
  });
});
