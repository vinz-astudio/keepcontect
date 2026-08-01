package com.keepcontact.app;

import android.os.Bundle;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        registerPlugin(PassivePingPlugin.class);
        // Created here rather than on the first poll: a `concern` push arriving
        // before the channel exists would be filed under a default-importance
        // channel, which shows no heads-up banner and makes no sound — the two
        // things that make it reach someone whose phone is face-down.
        NotifyWorker.ensureChannel(this);
        super.onCreate(savedInstanceState);
    }
}
