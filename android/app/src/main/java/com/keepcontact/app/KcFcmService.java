package com.keepcontact.app;

import androidx.work.OneTimeWorkRequest;
import androidx.work.WorkManager;
import com.google.firebase.messaging.FirebaseMessagingService;
import com.google.firebase.messaging.RemoteMessage;

/**
 * FCM fast path (ADR-0004 Phase 2).
 *
 * push-dispatch sends a DATA-ONLY wake tickle — no title, no body, no names.
 * On receipt we immediately run NotifyWorker, which pulls the actual unread
 * notifications from the HMAC-authenticated notify-feed endpoint and posts
 * them locally. Notification content therefore never transits Google; FCM
 * only learns that "this device should wake up now". The 15-minute periodic
 * poll remains as fallback for devices without Google services.
 */
public class KcFcmService extends FirebaseMessagingService {
    @Override
    public void onMessageReceived(RemoteMessage message) {
        WorkManager.getInstance(getApplicationContext())
            .enqueue(new OneTimeWorkRequest.Builder(NotifyWorker.class).build());
    }

    @Override
    public void onNewToken(String token) {
        // The web layer re-registers the current token on every app open
        // (register_fcm_token RPC is an idempotent upsert), so a rotated token
        // heals on next launch; no native-side upload needed.
    }
}
