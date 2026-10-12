package dev.alextsyrkin.fixmicts;

import android.Manifest;
import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.provider.Settings;
import android.os.Process;
import android.util.Log;

/** Public app-UID write; success is NOT proof of a connected voice service. */
final class Repair {
    static final String PACKAGE = "dev.alextsyrkin.fixmicts";
    static final String COMPONENT = "com.google.android.googlequicksearchbox/com.google.android.voiceinteraction.GsaVoiceInteractionService";
    private static final String KEY = "voice_interaction_service";
    private static final String ASSISTANT = "assistant";
    private static final String PREFS = "status";

    private Repair() {}

    static boolean hasPermission(Context context) {
        return context.checkSelfPermission(Manifest.permission.WRITE_SECURE_SETTINGS)
                == PackageManager.PERMISSION_GRANTED;
    }

    static synchronized String run(Context context, String origin) {
        String result;
        if (Process.myUid() / 100000 != 0) {
            result = "Not changed: only the primary Android user 0 is supported";
        } else if (!hasPermission(context)) {
            result = "Permission missing: WRITE_SECURE_SETTINGS";
        } else {
            try {
                String assistant = Settings.Secure.getString(context.getContentResolver(), ASSISTANT);
                String currentService = Settings.Secure.getString(context.getContentResolver(), KEY);
                // This Vivo was observed clearing VIS after reboot while retaining Google
                // as assistant. Restore an empty VIS only when that explicit Google choice
                // remains. Never replace a different, nonempty voice service or assistant.
                boolean missingService = currentService == null || currentService.isEmpty();
                if (!COMPONENT.equals(assistant)
                        || (!missingService && !COMPONENT.equals(currentService))) {
                    result = "Not changed: assistant is not Google or a different voice service is selected";
                } else {
                    boolean putSucceeded = Settings.Secure.putString(context.getContentResolver(), KEY, COMPONENT);
                    boolean readback = COMPONENT.equals(Settings.Secure.getString(context.getContentResolver(), KEY));
                    result = putSucceeded && readback ? "Write accepted and value read back; service connection NOT verified. Test MiCTS."
                            : "System settings provider rejected the write";
                }
            } catch (SecurityException e) {
                result = "Permission denied by Android/OriginOS: " + e.getMessage();
                Log.e("FixMiCTS", result, e);
            } catch (Exception e) {
                result = "Error: " + e.getClass().getSimpleName() + ": " + e.getMessage();
                Log.e("FixMiCTS", result, e);
            }
        }
        SharedPreferences p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        p.edit().putLong("time", System.currentTimeMillis()).putString("origin", origin)
                .putString("result", result).commit();
        Log.i("FixMiCTS", "Repair origin=" + origin + " uid=" + Process.myUid() + " result=" + result);
        return result;
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
