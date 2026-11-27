package com.shenmareparas.pathwise;

import android.Manifest;
import android.app.AlarmManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.os.Build;
import android.provider.Settings;
import org.json.JSONException;
import org.json.JSONObject;
import java.util.Iterator;

final class NotificationHelper {
    static final String EXTRA_CATEGORY = "pathwise_notification_category";
    static final String EXTRA_ID = "pathwise_notification_id";
    static final String EXTRA_CHANNEL = "pathwise_notification_channel";
    static final String EXTRA_TITLE = "pathwise_notification_title";
    static final String EXTRA_BODY = "pathwise_notification_body";

    static final String CHANNEL_DAILY = "pathwise_daily";
    static final String CHANNEL_STREAK = "pathwise_streak";
    static final String CHANNEL_INVITES = "pathwise_invites";

    private static final String PREFS = "pathwise_scheduled_notifications";

    private NotificationHelper() {}

    static void ensureChannels(Context context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return;
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        if (manager == null) return;
        manager.createNotificationChannel(new NotificationChannel(
                CHANNEL_DAILY,
                "Daily Challenge Reminders",
                NotificationManager.IMPORTANCE_DEFAULT
        ));
        manager.createNotificationChannel(new NotificationChannel(
                CHANNEL_STREAK,
                "Streak Reminders",
                NotificationManager.IMPORTANCE_DEFAULT
        ));
        manager.createNotificationChannel(new NotificationChannel(
                CHANNEL_INVITES,
                "Puzzle Invitations",
                NotificationManager.IMPORTANCE_LOW
        ));
    }

    static boolean canPostNotifications(Context context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                    != PackageManager.PERMISSION_GRANTED) {
                return false;
            }
        }
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        return manager == null || manager.areNotificationsEnabled();
    }

    static void openNotificationSettings(Context context) {
        Intent intent = new Intent();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            intent.setAction(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, context.getPackageName());
        } else {
            intent.setAction(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                    .setData(android.net.Uri.fromParts("package", context.getPackageName(), null));
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        try {
            context.startActivity(intent);
        } catch (RuntimeException ignored) {
        }
    }

    static void schedule(
            Context context,
            int id,
            String channel,
            String title,
            String body,
            String category,
            long triggerAtMillis
    ) {
        ensureChannels(context);
        long now = System.currentTimeMillis();
        if (triggerAtMillis <= now) {
            triggerAtMillis = now + 5000L;
        }
        AlarmManager alarms = context.getSystemService(AlarmManager.class);
        if (alarms == null) return;
        PendingIntent pending = alarmIntent(context, id, channel, title, body, category);
        alarms.cancel(pending);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pending);
        } else {
            alarms.set(AlarmManager.RTC_WAKEUP, triggerAtMillis, pending);
        }
        saveScheduled(context, id, channel, title, body, category, triggerAtMillis);
    }

    static void cancel(Context context, int id) {
        AlarmManager alarms = context.getSystemService(AlarmManager.class);
        if (alarms != null) {
            alarms.cancel(alarmIntent(context, id, CHANNEL_DAILY, "", "", ""));
        }
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        if (manager != null) {
            manager.cancel(id);
        }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .remove(String.valueOf(id))
                .apply();
    }

    static void cancelAll(Context context) {
        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        for (String key : prefs.getAll().keySet()) {
            try {
                cancel(context, Integer.parseInt(key));
            } catch (NumberFormatException ignored) {
            }
        }
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        if (manager != null) {
            manager.cancelAll();
        }
    }

    static void restoreScheduled(Context context) {
        ensureChannels(context);
        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        long now = System.currentTimeMillis();
        Iterator<String> keys = prefs.getAll().keySet().iterator();
        while (keys.hasNext()) {
            String key = keys.next();
            String raw = prefs.getString(key, null);
            if (raw == null) continue;
            try {
                JSONObject json = new JSONObject(raw);
                int id = json.getInt("id");
                long triggerAt = json.getLong("triggerAt");
                if (triggerAt <= now) {
                    prefs.edit().remove(key).apply();
                    continue;
                }
                schedule(
                        context,
                        id,
                        json.getString("channel"),
                        json.getString("title"),
                        json.getString("body"),
                        json.getString("category"),
                        triggerAt
                );
            } catch (JSONException error) {
                prefs.edit().remove(key).apply();
            }
        }
    }

    static void showNow(
            Context context,
            int id,
            String channel,
            String title,
            String body,
            String category
    ) {
        if (!canPostNotifications(context)) return;
        ensureChannels(context);
        Intent tapIntent = new Intent(context, MainActivity.class)
                .setAction("games.tabletop.pathwise.NOTIFICATION_TAP")
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP)
                .putExtra(EXTRA_CATEGORY, category);
        PendingIntent tapPending = PendingIntent.getActivity(
                context,
                id,
                tapIntent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );

        Notification.Builder builder = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                ? new Notification.Builder(context, channel)
                : new Notification.Builder(context);
        builder.setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(title)
                .setContentText(body)
                .setAutoCancel(true)
                .setContentIntent(tapPending);

        NotificationManager manager = context.getSystemService(NotificationManager.class);
        if (manager != null) {
            manager.notify(id, builder.build());
        }
    }

    static void removePersisted(Context context, int id) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .remove(String.valueOf(id))
                .apply();
    }

    private static PendingIntent alarmIntent(
            Context context,
            int id,
            String channel,
            String title,
            String body,
            String category
    ) {
        Intent intent = new Intent(context, NotificationReceiver.class)
                .putExtra(EXTRA_ID, id)
                .putExtra(EXTRA_CHANNEL, channel)
                .putExtra(EXTRA_TITLE, title)
                .putExtra(EXTRA_BODY, body)
                .putExtra(EXTRA_CATEGORY, category);
        return PendingIntent.getBroadcast(
                context,
                id,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );
    }

    private static void saveScheduled(
            Context context,
            int id,
            String channel,
            String title,
            String body,
            String category,
            long triggerAtMillis
    ) {
        try {
            JSONObject json = new JSONObject();
            json.put("id", id);
            json.put("channel", channel);
            json.put("title", title);
            json.put("body", body);
            json.put("category", category);
            json.put("triggerAt", triggerAtMillis);
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                    .edit()
                    .putString(String.valueOf(id), json.toString())
                    .apply();
        } catch (JSONException ignored) {
        }
    }
}
