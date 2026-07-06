package com.keepcontact.app;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.util.Log;
import com.google.android.gms.location.ActivityTransitionEvent;
import com.google.android.gms.location.ActivityTransitionResult;

public class ActivityTransitionReceiver extends BroadcastReceiver {
    private static final String TAG = "KeepContactPassive";

    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent == null) return;
        Log.d(TAG, "ActivityTransitionReceiver received intent: " + intent.getAction());

        if (ActivityTransitionResult.hasResult(intent)) {
            ActivityTransitionResult result = ActivityTransitionResult.extractResult(intent);
            if (result != null) {
                boolean hasTransitions = false;
                for (ActivityTransitionEvent event : result.getTransitionEvents()) {
                    Log.d(TAG, "GMS Transition Event: ActivityType=" + event.getActivityType() 
                        + ", TransitionType=" + event.getTransitionType());
                    hasTransitions = true;
                }
                if (hasTransitions) {
                    Log.d(TAG, "User activity transition observed. Triggering passive ping.");
                    PassivePing.ping(context);
                }
            }
        }
    }
}
