package com.shenmareparas.pathwise;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public class NotificationReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent == null) return;
        String action = intent.getAction();
        if (Intent.ACTION_BOOT_COMPLETED.equals(action)
                || Intent.ACTION_MY_PACKAGE_REPLACED.equals(action)
                || Intent.ACTION_TIMEZONE_CHANGED.equals(action)) {
            NotificationHelper.restoreScheduled(context);
            return;
        }
        int id = intent.getIntExtra(NotificationHelper.EXTRA_ID, -1);
        if (id < 0) return;
        String channel = intent.getStringExtra(NotificationHelper.EXTRA_CHANNEL);
        String title = intent.getStringExtra(NotificationHelper.EXTRA_TITLE);
        String body = intent.getStringExtra(NotificationHelper.EXTRA_BODY);
        String category = intent.getStringExtra(NotificationHelper.EXTRA_CATEGORY);
        if (channel == null) channel = NotificationHelper.CHANNEL_DAILY;
        if (title == null) title = "Pathwise";
        if (body == null) body = "Your next puzzle is waiting.";
        if (category == null) category = "invite";
        NotificationHelper.removePersisted(context, id);
        NotificationHelper.showNow(context, id, channel, title, body, category);
    }
}
