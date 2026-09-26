package com.keepcontact.app;

import android.content.Context;
import android.content.SharedPreferences;
import androidx.core.app.NotificationManagerCompat;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.util.UUID;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;
import org.json.JSONArray;
import org.json.JSONObject;

/** Push login state is independent of optional passive sensor consent. */
final class PushBindingStore {
    private static final String KEY_ALIAS = "keep_contact_push_binding_v2";
    private static final Object REVOKE_LOCK = new Object();
    static SharedPreferences prefs(Context context) {
        return context.getApplicationContext().getSharedPreferences("kc.push-session.v2", Context.MODE_PRIVATE);
    }

    static synchronized String configure(Context context, String owner, String bindingId,
        String revokeSecret, String url, String anonKey, String token, String legacyToken) throws Exception {
        SharedPreferences prefs = prefs(context);
        String generation = generation(context);
        boolean changed = !owner.equals(owner(context)) || generation.isEmpty()
            || (bindingId != null && !bindingId.equals(bindingId(context)));
        if (changed) {
            clear(context);
            generation = UUID.randomUUID().toString();
        }
        JSONObject secrets = activeSecrets(context);
        if (secrets == null) secrets = new JSONObject();
        if (revokeSecret != null) secrets.put("revoke_secret", revokeSecret);
        if (url != null) secrets.put("url", url.replaceAll("/+$", ""));
        if (anonKey != null) secrets.put("anon_key", anonKey);
        if (token != null) secrets.put("token", token);
        if (legacyToken != null) secrets.put("legacy_token", legacyToken);
        // Neither notification bearer nor revoke capability is plaintext on disk.
        SharedPreferences.Editor editor = prefs.edit().putString("active_secrets", encrypt(secrets.toString()).toString())
            .putString("owner", owner).putString("generation", generation);
        if (changed) editor.putString("binding_id", bindingId)
            .putString("notify_since", PassiveEvidenceContract.iso(System.currentTimeMillis()));
        if (!editor.commit()) {
            throw new IllegalStateException("Unable to persist push binding");
        }
        try { com.google.firebase.messaging.FirebaseMessaging.getInstance().setAutoInitEnabled(true); }
        catch (Exception ignored) { /* Polling remains available without Google services. */ }
        EvidenceUploadWorker.schedule(context);
        return generation;
    }

    static synchronized void configureFeed(Context context, String url, String token) {
        if (owner(context).isEmpty() || url == null || token == null || token.isEmpty()) return;
        try {
            JSONObject secrets = activeSecrets(context);
            if (secrets == null) secrets = new JSONObject();
            secrets.put("url", url.replaceAll("/+$", "")).put("token", token);
            prefs(context).edit().putString("active_secrets", encrypt(secrets.toString()).toString()).commit();
        } catch (Exception ignored) { /* Never persist credentials without encryption. */ }
    }

    static synchronized void clear(Context context) {
        SharedPreferences prefs = prefs(context);
        JSONObject secrets = activeSecrets(context);
        String bindingId = bindingId(context);
        JSONArray pending = pendingRevocations(context);
        try {
            if (NotificationActionQueue.isUuid(bindingId) && secrets != null && !secrets.optString("revoke_secret").isEmpty()) {
                // Outbox intentionally excludes feed token and account credentials.
                JSONObject revoke = new JSONObject().put("binding_id", bindingId)
                    .put("revoke_secret", secrets.getString("revoke_secret"))
                    .put("url", secrets.getString("url")).put("anon_key", secrets.getString("anon_key"));
                if (secrets.has("legacy_token")) revoke.put("legacy_token", secrets.getString("legacy_token"));
                pending.put(encrypt(revoke.toString()));
            }
        } catch (Exception exception) { throw new IllegalStateException("Unable to preserve push revocation", exception); }
        // Tombstone and owner invalidation share one durable write.
        if (!prefs.edit().putString("pending_revocations", pending.toString())
            .remove("owner").remove("generation").remove("binding_id").remove("active_secrets")
            .remove("actions").remove("completed_actions").remove("notify_since").commit()) {
            throw new IllegalStateException("Unable to clear push binding");
        }
        NotificationManagerCompat.from(context).cancelAll();
        try { com.google.firebase.messaging.FirebaseMessaging.getInstance().setAutoInitEnabled(false); }
        catch (Exception ignored) { }
        EvidenceUploadWorker.schedule(context);
    }

    static synchronized String owner(Context context) { return prefs(context).getString("owner", ""); }
    static synchronized String generation(Context context) { return prefs(context).getString("generation", ""); }
    static synchronized String bindingId(Context context) { return prefs(context).getString("binding_id", ""); }
    static synchronized boolean matches(Context context, String owner, String generation) {
        return NotificationActionQueue.matchesSession(owner(context), generation(context), owner, generation);
    }

    static synchronized JSONObject activeSecrets(Context context) {
        try { return decrypt(new JSONObject(prefs(context).getString("active_secrets", ""))); }
        catch (Exception ignored) { return null; }
    }
    static synchronized JSONArray pendingRevocations(Context context) {
        try { return new JSONArray(prefs(context).getString("pending_revocations", "[]")); }
        catch (Exception ignored) { return new JSONArray(); }
    }

    static boolean drainRevocations(Context context) {
        synchronized (REVOKE_LOCK) {
            while (true) {
                JSONObject encrypted;
                synchronized (PushBindingStore.class) {
                    JSONArray pending = pendingRevocations(context);
                    if (pending.length() == 0) return true;
                    encrypted = pending.optJSONObject(0);
                }
                HttpURLConnection connection = null;
                try {
                    JSONObject revoke = decrypt(encrypted);
                    connection = (HttpURLConnection) new URL(revoke.getString("url") + "/rest/v1/rpc/revoke_push_binding").openConnection();
                    connection.setRequestMethod("POST");
                    connection.setConnectTimeout(8000); connection.setReadTimeout(8000);
                    connection.setRequestProperty("Content-Type", "application/json");
                    connection.setRequestProperty("apikey", revoke.getString("anon_key"));
                    connection.setRequestProperty("Authorization", "Bearer " + revoke.getString("anon_key"));
                    connection.setDoOutput(true);
                    JSONObject body = new JSONObject().put("_binding_id", revoke.getString("binding_id"))
                        .put("_revoke_secret", revoke.getString("revoke_secret"));
                    if (revoke.has("legacy_token")) body.put("_legacy_token", revoke.getString("legacy_token"));
                    try (java.io.OutputStream output = connection.getOutputStream()) {
                        output.write(body.toString().getBytes(StandardCharsets.UTF_8));
                    }
                    if (connection.getResponseCode() != 200) return false;
                    StringBuilder response = new StringBuilder();
                    try (BufferedReader reader = new BufferedReader(new InputStreamReader(connection.getInputStream(), StandardCharsets.UTF_8))) {
                        String line; while ((line = reader.readLine()) != null) response.append(line);
                    }
                    if (!"true".equals(response.toString().trim())) return false;
                    synchronized (PushBindingStore.class) {
                        JSONArray pending = pendingRevocations(context), remaining = new JSONArray();
                        if (!encrypted.toString().equals(pending.optString(0))) return false;
                        for (int i = 1; i < pending.length(); i++) remaining.put(pending.opt(i));
                        if (!prefs(context).edit().putString("pending_revocations", remaining.toString()).commit()) return false;
                    }
                } catch (Exception ignored) { return false; }
                finally { if (connection != null) connection.disconnect(); }
            }
        }
    }

    private static SecretKey key() throws Exception {
        KeyStore store = KeyStore.getInstance("AndroidKeyStore"); store.load(null);
        if (store.containsAlias(KEY_ALIAS)) return ((KeyStore.SecretKeyEntry) store.getEntry(KEY_ALIAS, null)).getSecretKey();
        KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
        generator.init(new KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build());
        return generator.generateKey();
    }
    private static JSONObject encrypt(String value) throws Exception {
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding"); cipher.init(Cipher.ENCRYPT_MODE, key());
        return new JSONObject().put("iv", Base64.encodeToString(cipher.getIV(), Base64.NO_WRAP))
            .put("data", Base64.encodeToString(cipher.doFinal(value.getBytes(StandardCharsets.UTF_8)), Base64.NO_WRAP));
    }
    private static JSONObject decrypt(JSONObject value) throws Exception {
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.DECRYPT_MODE, key(), new GCMParameterSpec(128, Base64.decode(value.getString("iv"), Base64.NO_WRAP)));
        return new JSONObject(new String(cipher.doFinal(Base64.decode(value.getString("data"), Base64.NO_WRAP)), StandardCharsets.UTF_8));
    }
}
