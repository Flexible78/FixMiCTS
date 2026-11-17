package dev.alextsyrkin.fixmicts;

import android.Manifest;
import android.content.ContentResolver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.provider.Settings;
import android.os.Process;
import android.util.Log;

/** Public app-UID writes; success is NOT proof of a connected voice service or bound service. */
final class Repair {
    static final String PACKAGE = "dev.alextsyrkin.fixmicts";
    static final String COMPONENT = "com.google.android.googlequicksearchbox/com.google.android.voiceinteraction.GsaVoiceInteractionService";
    private static final String KEY = "voice_interaction_service";
    private static final String ASSISTANT = "assistant";
    private static final String PREFS = "status";

    // Vivid N.G. (com.ivianuu.oneplusgestures) exposes its gesture engine through an
    // accessibility service. OriginOS drops that service after some reboots; the same
    // Secure Settings write that the ADB shell used re-binds it without the manual
    // "Vivid N.G. requests permission..." confirmation dialog.
    private static final String VIVID_PACKAGE = "com.ivianuu.oneplusgestures";
    private static final String VIVID_SERVICE = "com.ivianuu.oneplusgestures/com.ivianuu.vivid.accessibility.VividAccessibilityService";
    private static final String A11Y_SERVICES_KEY = "enabled_accessibility_services";
    private static final String A11Y_ENABLED_KEY = "accessibility_enabled";
    // Public automation broadcast documented by Vivid (Tasker-style control).
    private static final String VIVID_TURN_ON = "com.ivianuu.vivid.TURN_GESTURES_ON";

    private Repair() {}

    static boolean hasPermission(Context context) {
        return context.checkSelfPermission(Manifest.permission.WRITE_SECURE_SETTINGS)
                == PackageManager.PERMISSION_GRANTED;
    }

    static synchronized String run(Context context, String origin) {
        String result = runVoiceInteraction(context) + "\n" + runVivid(context);
        SharedPreferences p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        p.edit().putLong("time", System.currentTimeMillis()).putString("origin", origin)
                .putString("result", result).commit();
        Log.i("FixMiCTS", "Repair origin=" + origin + " uid=" + Process.myUid() + " result=" + result.replace('\n', ' '));
        return result;
    }

    private static String runVoiceInteraction(Context context) {
        if (Process.myUid() / 100000 != 0) {
            return "MiCTS/VIS: not changed: only the primary Android user 0 is supported";
        }
        if (!hasPermission(context)) {
            return "MiCTS/VIS: permission missing: WRITE_SECURE_SETTINGS";
        }
        try {
            String assistant = Settings.Secure.getString(context.getContentResolver(), ASSISTANT);
            String currentService = Settings.Secure.getString(context.getContentResolver(), KEY);
            // This Vivo was observed clearing VIS after reboot while retaining Google
            // as assistant. Restore an empty VIS only when that explicit Google choice
            // remains. Never replace a different, nonempty voice service or assistant.
            boolean missingService = currentService == null || currentService.isEmpty();
            if (!COMPONENT.equals(assistant)
                    || (!missingService && !COMPONENT.equals(currentService))) {
                return "MiCTS/VIS: not changed: assistant is not Google or a different voice service is selected";
            }
            boolean putSucceeded = Settings.Secure.putString(context.getContentResolver(), KEY, COMPONENT);
            boolean readback = COMPONENT.equals(Settings.Secure.getString(context.getContentResolver(), KEY));
            return putSucceeded && readback
                    ? "MiCTS/VIS: write accepted and value read back; service connection NOT verified. Test MiCTS."
                    : "MiCTS/VIS: system settings provider rejected the write";
        } catch (SecurityException e) {
            Log.e("FixMiCTS", "VIS write denied", e);
            return "MiCTS/VIS: permission denied by Android/OriginOS: " + e.getMessage();
        } catch (Exception e) {
            Log.e("FixMiCTS", "VIS write error", e);
            return "MiCTS/VIS: error: " + e.getClass().getSimpleName() + ": " + e.getMessage();
        }
    }

    private static String runVivid(Context context) {
        if (Process.myUid() / 100000 != 0) {
            return "Vivid: not changed: only the primary Android user 0 is supported";
        }
        if (!hasPermission(context)) {
            return "Vivid: permission missing: WRITE_SECURE_SETTINGS";
        }
        try {
            context.getPackageManager().getPackageInfo(VIVID_PACKAGE, 0);
        } catch (PackageManager.NameNotFoundException e) {
            return "Vivid: not installed; skipped";
        }
        try {
            ContentResolver cr = context.getContentResolver();
            String current = Settings.Secure.getString(cr, A11Y_SERVICES_KEY);
            boolean present = false;
            StringBuilder joined = new StringBuilder();
            if (current != null) {
                for (String service : current.split(":")) {
                    if (service.isEmpty()) continue;
                    if (VIVID_SERVICE.equals(service)) present = true;
                    if (joined.length() > 0) joined.append(':');
                    joined.append(service);
                }
            }
            boolean changed = false;
            if (!present) {
                // Append, never replace: other accessibility services stay untouched.
                if (joined.length() > 0) joined.append(':');
                joined.append(VIVID_SERVICE);
                Settings.Secure.putString(cr, A11Y_SERVICES_KEY, joined.toString());
                changed = true;
            }
            if (Settings.Secure.getInt(cr, A11Y_ENABLED_KEY, 0) != 1) {
                Settings.Secure.putInt(cr, A11Y_ENABLED_KEY, 1);
                changed = true;
            }
            String readServices = Settings.Secure.getString(cr, A11Y_SERVICES_KEY);
            int readEnabled = Settings.Secure.getInt(cr, A11Y_ENABLED_KEY, 0);
            boolean confirmed = readEnabled == 1 && readServices != null
                    && (":" + readServices + ":").contains(":" + VIVID_SERVICE + ":");
            // Best effort: nudge the already-bound engine to turn gestures on.
            try {
                Intent turnOn = new Intent(VIVID_TURN_ON);
                turnOn.setPackage(VIVID_PACKAGE);
                context.sendBroadcast(turnOn);
            } catch (Exception ignored) {
                // Broadcast is optional; the accessibility binding is the primary fix.
            }
            if (!confirmed) {
                return "Vivid: write rejected by the settings provider";
            }
            return changed
                    ? "Vivid: accessibility enabled and read back. Verify gestures."
                    : "Vivid: already enabled";
        } catch (SecurityException e) {
            Log.e("FixMiCTS", "Vivid write denied", e);
            return "Vivid: permission denied by Android/OriginOS: " + e.getMessage();
        } catch (Exception e) {
            Log.e("FixMiCTS", "Vivid write error", e);
            return "Vivid: error: " + e.getClass().getSimpleName() + ": " + e.getMessage();
        }
    }

    static String lastRun(Context context) {
        SharedPreferences p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        long ts = p.getLong("time", 0);
        if (ts == 0) return "No repair attempted yet";
        return "Last attempt: " + android.text.format.DateFormat.format("yyyy-MM-dd HH:mm:ss", ts)
                + " (" + p.getString("origin", "?") + ")\n"
                + p.getString("result", "unknown");
    }
}
