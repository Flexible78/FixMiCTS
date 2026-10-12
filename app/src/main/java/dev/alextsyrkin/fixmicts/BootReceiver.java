package dev.alextsyrkin.fixmicts;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Process;
import android.os.SystemClock;
import android.provider.Settings;
import android.util.Log;

/** One short app-UID write during the delivered boot broadcast, not a scheduled job. */
public final class BootReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context context, Intent intent) {
        String action = intent == null ? null : intent.getAction();
        if (!Intent.ACTION_BOOT_COMPLETED.equals(action)) return;
        if (Process.myUid() / 100000 != 0) return;
        Log.i("FixMiCTS", "Receiver action=" + action + " uid=" + Process.myUid());
        final Context app = context.getApplicationContext();
        final PendingResult pending = goAsync();
        try {
            new Thread(() -> {
                long started = SystemClock.elapsedRealtime();
                try {
                    synchronized (BootReceiver.class) {
                        SharedPreferences p = app.getSharedPreferences("status", Context.MODE_PRIVATE);
                        int bootCount = Settings.Global.getInt(app.getContentResolver(), "boot_count", -1);
                        p.edit().putLong("event_time", System.currentTimeMillis())
                                .putString("event", action).putString("schedule", "Direct boot worker; no JobScheduler")
                                .commit();
                        if (bootCount >= 0 && p.getInt("attempted_boot_count", -2) == bootCount) {
                            Log.i("FixMiCTS", "Duplicate boot ignored boot_count=" + bootCount);
                            return;
                        }
                        // Mark before writing: at most one automatic attempt per readable boot count.
                        // Any failed/skipped attempt can still be retried with the manual button.
                        if (bootCount >= 0 && !p.edit().putInt("attempted_boot_count", bootCount).commit()) {
                            throw new IllegalStateException("Cannot persist boot-attempt guard");
                        }
                        Log.i("FixMiCTS", "Direct boot repair start boot_count=" + bootCount);
                        Repair.run(app, "boot receiver");
                    }
                } catch (Exception e) {
                    Log.e("FixMiCTS", "Direct boot repair failed", e);
                    app.getSharedPreferences("status", Context.MODE_PRIVATE).edit()
                            .putString("schedule", "Direct boot error: " + e.getClass().getSimpleName()).commit();
                } finally {
                    Log.i("FixMiCTS", "Boot worker finished duration_ms=" + (SystemClock.elapsedRealtime() - started));
                    pending.finish();
                }
            }, "FixMiCTS-boot-once").start();
        } catch (Exception e) {
            Log.e("FixMiCTS", "Cannot start direct boot worker", e);
            pending.finish();
        }
    }
}
