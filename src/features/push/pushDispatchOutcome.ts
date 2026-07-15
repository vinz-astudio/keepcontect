// Deliberate duplicate of supabase/functions/push-dispatch/outcome.ts (edge runtime cannot import across the src/ boundary at deploy time); keep in sync.

export interface DeliveryOutcomeInput {
  hasWebPushConfig: boolean;
  hasFcmConfig: boolean;
  dbSubsCount: number;
  dbFcmCount: number;
  webPushSuccessCount: number;
  fcmSuccessCount: number;
}

/**
 * Pure function to determine the outcome of a notification delivery attempt.
 *
 * Outcomes:
 * - 'sent': >= 1 successful delivery (either Web Push or FCM).
 * - 'no_target': recipient has zero subscriptions AND zero FCM tokens in the DB.
 * - 'retry': recipient has targets, but zero successful deliveries occurred (transient failure).
 */
export function determineDeliveryOutcome(input: DeliveryOutcomeInput): 'sent' | 'no_target' | 'retry' {
  const {
    dbSubsCount,
    dbFcmCount,
    webPushSuccessCount,
    fcmSuccessCount,
  } = input;

  // Property B: 'no_target' is strictly decided by zero DB subscriptions AND zero FCM tokens for the recipient.
  if (dbSubsCount === 0 && dbFcmCount === 0) {
    return 'no_target';
  }

  // Property B: 'sent' is decided by at least one successful delivery.
  if (webPushSuccessCount > 0 || fcmSuccessCount > 0) {
    return 'sent';
  }

  // Otherwise, if targets exist but no deliveries succeeded, it's a transient failure.
  return 'retry';
}
