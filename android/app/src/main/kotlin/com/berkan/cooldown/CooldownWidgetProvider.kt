package com.berkan.cooldown

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews

class CooldownWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, appWidgetIds: IntArray) {
        updateAll(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_REFRESH) updateAll(context) else super.onReceive(context, intent)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        val editor = prefs(context).edit()
        appWidgetIds.forEach { editor.remove(widgetKey(it)) }
        editor.apply()
    }

    override fun onDisabled(context: Context) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.cancel(refreshIntent(context))
    }

    companion object {
        const val ACTION_REFRESH = "com.berkan.cooldown.REFRESH"
        private const val HALF_HOUR_MS = 1_800_000L

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, CooldownWidgetProvider::class.java))
            val p = prefs(context)

            // A widget pinned from inside the app gets the cooldown the user picked there.
            val pending = p.getString("pending_pin", null)
            if (pending != null) {
                val unmapped = ids.firstOrNull { p.getString(widgetKey(it), null) == null }
                if (unmapped != null) {
                    p.edit().putString(widgetKey(unmapped), pending).remove("pending_pin").apply()
                }
            }

            val all = Cooldown.loadAll(context)
            val defaultFormat = p.getString("default_display", "days") ?: "days"
            val now = System.currentTimeMillis()
            var nextRefresh = now + HALF_HOUR_MS

            for (id in ids) {
                val cooldownId = p.getString(widgetKey(id), null)
                val cooldown = all.firstOrNull { it.id == cooldownId }
                val views = RemoteViews(context.packageName, R.layout.cooldown_widget)

                if (cooldown == null) {
                    views.setTextViewText(R.id.title, "⏳ Cooldown")
                    views.setTextViewText(R.id.value, if (cooldownId == null) "Tap" else "?")
                    views.setTextViewText(R.id.label, if (cooldownId == null) "to choose a cooldown" else "not found — tap to choose")
                    views.setViewVisibility(R.id.progress, View.GONE)
                    views.setInt(R.id.bg, "setColorFilter", 0xFF6B6B6B.toInt())
                    views.setOnClickPendingIntent(R.id.root, configIntent(context, id))
                } else {
                    val (start, end) = cooldown.currentCycle(now)
                    val format = if (cooldown.display == "default") defaultFormat else cooldown.display
                    val finished = end <= now
                    views.setTextViewText(R.id.title, "${cooldown.emoji} ${cooldown.name}")
                    if (finished) {
                        views.setTextViewText(R.id.value, if (cooldown.repeats) "Ready" else "Done")
                        views.setTextViewText(R.id.label, if (cooldown.repeats) "tap to mark done" else "🎉")
                    } else {
                        val (value, label) = CooldownFormat.remaining(now, end, format)
                        views.setTextViewText(R.id.value, value)
                        views.setTextViewText(R.id.label, label)
                        nextRefresh = minOf(nextRefresh, end + 1000)
                        if (CooldownFormat.isFineGrained(now, end, format)) {
                            nextRefresh = minOf(nextRefresh, now + 60_000)
                        }
                    }
                    val total = (end - start).coerceAtLeast(1)
                    val pct = (((now - start).toDouble() / total) * 100).toInt().coerceIn(0, 100)
                    views.setViewVisibility(R.id.progress, View.VISIBLE)
                    views.setProgressBar(R.id.progress, 100, pct, false)
                    views.setInt(R.id.bg, "setColorFilter", cooldown.color)
                    views.setOnClickPendingIntent(R.id.root, openAppIntent(context))
                }
                manager.updateAppWidget(id, views)
            }

            if (ids.isNotEmpty()) scheduleRefresh(context, nextRefresh)
        }

        /** Inexact alarm (no special permission needed) to keep the widget current. */
        private fun scheduleRefresh(context: Context, atMs: Long) {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            am.set(AlarmManager.RTC, atMs, refreshIntent(context))
        }

        private fun refreshIntent(context: Context): PendingIntent {
            val intent = Intent(context, CooldownWidgetProvider::class.java).apply {
                action = ACTION_REFRESH
            }
            return PendingIntent.getBroadcast(
                context, 0, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun openAppIntent(context: Context): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            return PendingIntent.getActivity(
                context, 1, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun configIntent(context: Context, appWidgetId: Int): PendingIntent {
            val intent = Intent(context, CooldownConfigActivity::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            return PendingIntent.getActivity(
                context, 1000 + appWidgetId, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }
}
