package com.keepcontact.app;

import android.content.Context;
import android.content.Intent;
import java.util.UUID;
import org.json.JSONArray;
import org.json.JSONObject;

/** Cold and warm notification taps use the same persisted exact-target queue. */
final class NotificationActionQueue {
    static final String EXTRA_ACTION = "kcNotificationActionV2";
    private static volatile Runnable onPending;

    static final class Action {
        final String eventId, notificationId, alertId, recipientUserId, kind, action;
        private Action(String notificationId, String alertId, String owner, String kind, String action) {
            this.notificationId = notificationId; this.alertId = alertId;
            this.recipientUserId = owner; this.kind = kind; this.action = action;
            this.eventId = notificationId + ":" + action;
        }
        static Action create(String notificationId, String alertId, String owner, String kind, String action, int version) {
            if (version != 2 || !isUuid(notificationId) || !isUuid(owner) || kind == null || kind.isEmpty()) return null;
            if (!"open".equals(action) && !"acknowledge_safe".equals(action)) return null;
            if (alertId != null && !alertId.isEmpty() && !isUuid(alertId)) return null;
            if ("acknowledge_safe".equals(action) && (!isUuid(alertId) || !("self".equals(kind) || "concern".equals(kind)))) return null;
            return new Action(notificationId, alertId, owner, kind, action);
        }
        JSONObject json(String generation) throws Exception {
            JSONObject json = new JSONObject();
            json.put("contractVersion", 2).put("eventId", eventId).put("notificationId", notificationId)
                .put("alertId", alertId == null || alertId.isEmpty() ? JSONObject.NULL : alertId)
                .put("recipientUserId", recipientUserId).put("kind", kind).put("action", action)
                .put("generation", generation);
            return json;
        }
    }

    static boolean isUuid(String value) {
        if (value == null || value.length() != 36) return false;
        try { return UUID.fromString(value).toString().equalsIgnoreCase(value); }
        catch (IllegalArgumentException ignored) { return false; }
    }

    static boolean matchesSession(String currentOwner, String currentGeneration, String owner, String generation) {
        return currentOwner != null && !currentOwner.isEmpty() && currentGeneration != null && !currentGeneration.isEmpty()
            && currentOwner.equals(owner) && currentGeneration.equals(generation);
    }

    static void attach(Intent intent, String id, String alert, String owner, String kind, String action, String generation, String pushBindingId) {
        Action value = Action.create(id, alert, owner, kind, action, 2);
        if (value == null) return;
        try {
            intent.putExtra(EXTRA_ACTION, value.json(generation).put("pushBindingId", pushBindingId).toString());
            // Android PendingIntent ignores extras when deciding identity.
            intent.setData(android.net.Uri.parse("kc-notification://" + id + "/" + action + "/" + generation));
        } catch (Exception ignored) { }
    }

    static void capture(Context context, Intent intent) {
        if (intent == null) return;
        String raw = intent.getStringExtra(EXTRA_ACTION);
        if (raw == null) return; // Legacy taps may open KC, never confirm an alert.
        try {
            JSONObject json = new JSONObject(raw);
            Action action = Action.create(json.optString("notificationId"), json.optString("alertId", null),
                json.optString("recipientUserId"), json.optString("kind"), json.optString("action"), json.optInt("contractVersion"));
            String generation = json.optString("generation");
            synchronized (PushBindingStore.class) {
                if (action == null || !PushBindingStore.matches(context, action.recipientUserId, generation)) return;
                String bindingId = json.optString("pushBindingId");
                if ("acknowledge_safe".equals(action.action)
                    && (!isUuid(bindingId) || !bindingId.equals(PushBindingStore.bindingId(context)))) return;
                JSONArray completed = completed(context);
                for (int i = 0; i < completed.length(); i++) {
                    if (action.eventId.equals(completed.optString(i))) {
                        intent.removeExtra(EXTRA_ACTION);
                        return;
                    }
                }
                JSONArray queue = pending(context);
                for (int i = 0; i < queue.length(); i++) {
                    if (action.eventId.equals(queue.getJSONObject(i).optString("eventId"))) {
                        intent.removeExtra(EXTRA_ACTION);
                        return;
                    }
                }
                queue.put(action.json(generation).put("pushBindingId", bindingId));
                if (!PushBindingStore.prefs(context).edit().putString("actions", queue.toString()).commit()) return;
            }
            intent.removeExtra(EXTRA_ACTION);
            Runnable callback = onPending;
            if (callback != null) callback.run();
        } catch (Exception ignored) { /* Malformed external intents fail closed. */ }
    }

    static JSONArray pending(Context context) {
        synchronized (PushBindingStore.class) {
            try { return new JSONArray(PushBindingStore.prefs(context).getString("actions", "[]")); }
            catch (Exception ignored) { return new JSONArray(); }
        }
    }

    static void complete(Context context, String eventId, String generation) {
        synchronized (PushBindingStore.class) {
            if (!PushBindingStore.generation(context).equals(generation)) return;
            JSONArray current = pending(context), remaining = new JSONArray();
            boolean found = false;
            for (int i = 0; i < current.length(); i++) {
                JSONObject value = current.optJSONObject(i);
                if (value != null && !eventId.equals(value.optString("eventId"))) remaining.put(value);
                else if (value != null) found = true;
            }
            if (!found) return;
            JSONArray oldCompleted = completed(context), completed = new JSONArray();
            for (int i = Math.max(0, oldCompleted.length() - 255); i < oldCompleted.length(); i++) completed.put(oldCompleted.opt(i));
            completed.put(eventId);
            PushBindingStore.prefs(context).edit().putString("actions", remaining.toString())
                .putString("completed_actions", completed.toString()).commit();
        }
    }

    private static JSONArray completed(Context context) {
        try { return new JSONArray(PushBindingStore.prefs(context).getString("completed_actions", "[]")); }
        catch (Exception ignored) { return new JSONArray(); }
    }

    static void listen(Runnable callback) { onPending = callback; }
}
