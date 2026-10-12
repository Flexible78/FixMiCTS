package dev.alextsyrkin.fixmicts;

import android.app.Activity;
import android.graphics.Color;
import android.os.Bundle;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.graphics.Typeface;
import android.view.Gravity;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class MainActivity extends Activity {
    private TextView status;
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final String grantCommand = "adb shell pm grant --user 0 " + Repair.PACKAGE
            + " android.permission.WRITE_SECURE_SETTINGS";

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private TextView text(String value, int size, int color) {
        TextView v = new TextView(this);
        v.setText(value);
        v.setTextSize(size);
        v.setTextColor(color);
        v.setPadding(0, dp(9), 0, dp(9));
        return v;
    }

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.setBackgroundColor(Color.rgb(13, 17, 28));
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(24), dp(42), dp(24), dp(24));
        scroll.addView(root);

        TextView title = text("Fix MiCTS", 30, Color.WHITE);
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        root.addView(title);
        root.addView(text("Vivo / OriginOS • Google VoiceInteractionService", 14, 0xffa6b4ce));
        root.addView(text("Одна короткая операция после загрузки. Без интернета, постоянного сервиса и периодического таймера.", 15, 0xffc8d3e8));
        status = text("", 15, 0xffe0e8f8);
        root.addView(status);

        Button fix = new Button(this);
        fix.setText("FIX NOW");
        root.addView(fix, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(58)));
        fix.setOnClickListener(v -> {
            fix.setEnabled(false);
            worker.submit(() -> {
                String outcome = Repair.run(getApplicationContext(), "manual button");
                runOnUiThread(() -> {
                    if (!isDestroyed()) { refresh(outcome); fix.setEnabled(true); }
                });
            });
        });

        Button refresh = new Button(this);
        refresh.setText("ОБНОВИТЬ СТАТУС");
        root.addView(refresh, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(52)));
        refresh.setOnClickListener(v -> refresh(null));

        root.addView(text("Первичная настройка: разрешение через ADB один раз", 14, 0xffa6b4ce));
        TextView command = text(grantCommand, 14, 0xffc0e0fb);
        command.setTextIsSelectable(true);
        root.addView(command);
        Button copy = new Button(this);
        copy.setText("КОПИРОВАТЬ КОМАНДУ");
        root.addView(copy);
        copy.setOnClickListener(v -> {
            ClipboardManager cm = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
            if (cm != null) cm.setPrimaryClip(ClipData.newPlainText("ADB permission", grantCommand));
        });

        root.addView(text("Включите Автозапуск только для Fix MiCTS в OriginOS. После загрузки выполняется одна попытка прямо из полученного события BOOT_COMPLETED, без JobScheduler. OriginOS может блокировать доставку события. Резерв: FIX NOW. Успешная запись не доказывает подключение службы — проверьте MiCTS.", 14, 0xffa6b4ce));
        setContentView(scroll);
        refresh(null);
    }

    private void refresh(String immediate) {
        String prefix = Repair.hasPermission(this) ? "Разрешение ADB: GRANTED (выдано)" : "Разрешение ADB: NOT GRANTED (не выдано)";
        android.content.SharedPreferences p = getSharedPreferences("status", MODE_PRIVATE);
        long eventTime = p.getLong("event_time", 0);
        String event = eventTime == 0 ? "Boot/update event: not recorded" : "Event: " + p.getString("event", "?")
                + "\n" + android.text.format.DateFormat.format("yyyy-MM-dd HH:mm:ss", eventTime)
                + "\n" + p.getString("schedule", "not scheduled");
        status.setText(prefix + "\n\n" + (immediate != null ? immediate + "\n\n" : "") + Repair.lastRun(this) + "\n\n" + event);
    }

    @Override protected void onResume() {
        super.onResume();
        if (status != null) refresh(null);
    }
    @Override protected void onDestroy() {
        worker.shutdownNow();
        super.onDestroy();
    }
}
