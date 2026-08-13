package com.keepcontact.app;

import static org.junit.Assert.assertEquals;

import android.provider.Settings;
import org.junit.Test;

public class NotificationSettingsIntentContractTest {
    @Test
    public void usesNotificationSettingsOnAndroidEightAndNewer() {
        assertEquals(
            Settings.ACTION_APP_NOTIFICATION_SETTINGS,
            PassivePingPlugin.notificationSettingsActionForSdk(26));
    }

    @Test
    public void fallsBackToApplicationDetailsOnAndroidSixAndSeven() {
        assertEquals(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            PassivePingPlugin.notificationSettingsActionForSdk(23));
        assertEquals(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            PassivePingPlugin.notificationSettingsActionForSdk(25));
    }
}
