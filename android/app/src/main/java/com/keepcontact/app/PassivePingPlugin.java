package com.keepcontact.app;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

@CapacitorPlugin(name = "PassivePing")
public class PassivePingPlugin extends Plugin {
    @PluginMethod
    public void configure(PluginCall call) {
        String supabaseUrl = call.getString("supabaseUrl");
        String token = call.getString("token");
        if (supabaseUrl == null || token == null || token.length() == 0) {
            call.reject("supabaseUrl and token are required");
            return;
        }
        PassivePing.configure(getContext(), supabaseUrl, token);
        call.resolve(new JSObject());
    }

    @PluginMethod
    public void clear(PluginCall call) {
        PassivePing.clear(getContext());
        call.resolve(new JSObject());
    }

    @PluginMethod
    public void pingApp(PluginCall call) {
        PassivePing.pingApp(getContext());
        call.resolve(new JSObject());
    }

    @Override
    protected void handleOnResume() {
        PassivePing.pingApp(getContext());
    }
}
