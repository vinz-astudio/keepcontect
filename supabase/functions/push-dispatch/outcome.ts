// Deliberate duplicate of src/features/push/pushDispatchOutcome.ts (edge runtime cannot import across the src/ boundary at deploy time); keep in sync.

export interface DeliveryOutcomeInput {
  hasWebPushConfig: boolean;
  hasFcmConfig: boolean;
  /** Recipient has an android-apk or ios-app client that reported recently. */
  hasNativeInstall: boolean;
  dbSubsCount: number;
  dbFcmCount: number;
  webPushSuccessCount: number;
  fcmSuccessCount: number;
}

export type DeliveryOutcome = 'sent' | 'no_target' | 'retry' | 'native_missed';

/**
 * Pure function to determine the outcome of a notification delivery attempt.
 *
 * A phone that is locked in someone's pocket is the only target that matters
 * for an unusual-silence alert, so "delivered" has to mean the native device
 * was reached. Counting any single Web Push success as delivery is what let a
 * dead Android FCM channel stay invisible for 26 days: the recipient's unused
 * desktop browser kept stamping notifications 'sent'.
 *
 * Outcomes:
 * - 'sent': the native device was reached, or the recipient has no native
 *   install and a Web Push succeeded.
 * - 'native_missed': a native install exists but holds no push token, so
 *   nothing can wake it. Terminal — retrying cannot conjure a token, and this
 *   is the value to alarm on.
 * - 'no_target': recipient has no native install, no subscriptions and no
 *   tokens. Benign: they never enabled push.
 * - 'retry': targets exist and the attempt failed in a way that may be
 *   transient. finalize_notification_delivery turns the 5th retry into
 *   'failed'.
 */
export function determineDeliveryOutcome(input: DeliveryOutcomeInput): DeliveryOutcome {
  const {
    hasNativeInstall,
    dbSubsCount,
    dbFcmCount,
    webPushSuccessCount,
    fcmSuccessCount,
  } = input;

  // The device that can actually wake the user was reached.
  if (fcmSuccessCount > 0) {
    return 'sent';
  }

  if (hasNativeInstall) {
    // No token for a phone we know exists: the wake channel is broken, not
    // busy. Retrying the same emptiness would only repeat the Web Push.
    if (dbFcmCount === 0) {
      return 'native_missed';
    }
    // A token exists but no native send succeeded — worth another attempt.
    return 'retry';
  }

  // 'no_target' is strictly decided by zero DB subscriptions and zero FCM tokens.
  if (dbSubsCount === 0 && dbFcmCount === 0) {
    return 'no_target';
  }

  if (webPushSuccessCount > 0) {
    return 'sent';
  }

  // Targets exist but no delivery succeeded: transient failure.
  return 'retry';
}
