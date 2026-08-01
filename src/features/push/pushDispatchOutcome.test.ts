import { describe, it, expect } from 'vitest';
import { determineDeliveryOutcome } from './pushDispatchOutcome';

describe('pushDispatchOutcome', () => {
  it('returns no_target when recipient has zero DB subscriptions and zero FCM tokens', () => {
    const outcome = determineDeliveryOutcome({
      hasWebPushConfig: true,
      hasFcmConfig: true,
      hasNativeInstall: false,
      dbSubsCount: 0,
      dbFcmCount: 0,
      webPushSuccessCount: 0,
      fcmSuccessCount: 0,
    });
    expect(outcome).toBe('no_target');
  });

  it('returns sent when there is at least one successful Web Push delivery', () => {
    const outcome = determineDeliveryOutcome({
      hasWebPushConfig: true,
      hasFcmConfig: true,
      hasNativeInstall: false,
      dbSubsCount: 1,
      dbFcmCount: 0,
      webPushSuccessCount: 1,
      fcmSuccessCount: 0,
    });
    expect(outcome).toBe('sent');
  });

  it('returns sent when there is at least one successful FCM delivery', () => {
    const outcome = determineDeliveryOutcome({
      hasWebPushConfig: true,
      hasFcmConfig: true,
      hasNativeInstall: false,
      dbSubsCount: 0,
      dbFcmCount: 1,
      webPushSuccessCount: 0,
      fcmSuccessCount: 1,
    });
    expect(outcome).toBe('sent');
  });

  it('returns retry when targets exist in database but all attempts fail', () => {
    const outcome = determineDeliveryOutcome({
      hasWebPushConfig: true,
      hasFcmConfig: true,
      hasNativeInstall: false,
      dbSubsCount: 1,
      dbFcmCount: 1,
      webPushSuccessCount: 0,
      fcmSuccessCount: 0,
    });
    expect(outcome).toBe('retry');
  });

  it('asserts FCM is attempted/sent when VAPID is absent but FCM is configured', () => {
    // When VAPID is absent (hasWebPushConfig = false) and FCM is configured (hasFcmConfig = true),
    // if we have FCM tokens in the DB, we attempt to deliver FCM.
    // Here we assert that outcome reflects FCM success independent of VAPID config presence.
    const input = {
      hasWebPushConfig: false,
      hasFcmConfig: true,
      hasNativeInstall: false,
      dbSubsCount: 1, // Has a Web Push sub in DB, but VAPID is absent
      dbFcmCount: 1,  // Has FCM token in DB, FCM is configured
      webPushSuccessCount: 0, // 0 because VAPID is absent, so no Web Push attempts can succeed
      fcmSuccessCount: 1,     // FCM succeeded
    };

    const outcome = determineDeliveryOutcome(input);
    expect(outcome).toBe('sent');
  });

  it('returns retry when VAPID is absent and FCM fails, but targets exist', () => {
    const input = {
      hasWebPushConfig: false,
      hasFcmConfig: true,
      hasNativeInstall: false,
      dbSubsCount: 1,
      dbFcmCount: 1,
      webPushSuccessCount: 0,
      fcmSuccessCount: 0,
    };

    const outcome = determineDeliveryOutcome(input);
    expect(outcome).toBe('retry');
  });

  // The concern that started this: a recipient whose phone is an APK install
  // had zero FCM tokens, so nothing could wake the phone — yet a Web Push to a
  // browser they were not holding stamped the row 'sent'.
  describe('native reachability', () => {
    it('returns native_missed when a native install exists but holds no FCM token, even if Web Push succeeded', () => {
      const outcome = determineDeliveryOutcome({
        hasWebPushConfig: true,
        hasFcmConfig: true,
        hasNativeInstall: true,
        dbSubsCount: 2,
        dbFcmCount: 0,
        webPushSuccessCount: 1,
        fcmSuccessCount: 0,
      });
      expect(outcome).toBe('native_missed');
    });

    it('returns native_missed when a native install has no token and no other target at all', () => {
      const outcome = determineDeliveryOutcome({
        hasWebPushConfig: true,
        hasFcmConfig: true,
        hasNativeInstall: true,
        dbSubsCount: 0,
        dbFcmCount: 0,
        webPushSuccessCount: 0,
        fcmSuccessCount: 0,
      });
      // Not 'no_target': a phone is out there expecting to be woken.
      expect(outcome).toBe('native_missed');
    });

    it('returns retry when a native install holds tokens but every native send failed', () => {
      const outcome = determineDeliveryOutcome({
        hasWebPushConfig: true,
        hasFcmConfig: true,
        hasNativeInstall: true,
        dbSubsCount: 1,
        dbFcmCount: 1,
        webPushSuccessCount: 1,
        fcmSuccessCount: 0,
      });
      // A token exists, so the failure may be transient and is worth retrying.
      expect(outcome).toBe('retry');
    });

    it('returns sent when the native device itself was reached', () => {
      const outcome = determineDeliveryOutcome({
        hasWebPushConfig: true,
        hasFcmConfig: true,
        hasNativeInstall: true,
        dbSubsCount: 0,
        dbFcmCount: 1,
        webPushSuccessCount: 0,
        fcmSuccessCount: 1,
      });
      expect(outcome).toBe('sent');
    });

    it('keeps no_target for a recipient with no native install and no targets', () => {
      const outcome = determineDeliveryOutcome({
        hasWebPushConfig: true,
        hasFcmConfig: true,
        hasNativeInstall: false,
        dbSubsCount: 0,
        dbFcmCount: 0,
        webPushSuccessCount: 0,
        fcmSuccessCount: 0,
      });
      expect(outcome).toBe('no_target');
    });
  });
});
