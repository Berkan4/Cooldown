package com.berkan.cooldown

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** How the title line is written in a layout. */
private enum class TitleStyle { EMOJI_ONLY, STACKED, INLINE }

/**
 * One layout per widget size. A layout is used once the widget is at least
 * [minWidthDp] x [minHeightDp]; of those that fit, the biggest one wins
 * (the same rule Android 12+ applies to the size map in [CooldownWidgetProvider]).
 */
private class WidgetLayout(
    val layoutId: Int,
    val minWidthDp: Float,
    val minHeightDp: Float,
    val title: TitleStyle,
    val showEnds: Boolean = false,
) {
    fun fits(widthDp: Float, heightDp: Float) = widthDp >= minWidthDp && heightDp >= minHeightDp
    val area get() = minWidthDp * minHeightDp
}

// One cell is roughly 57-73dp wide and 50-102dp high, depending on launcher and orientation.
private val LAYOUTS = listOf(
    WidgetLayout(R.layout.cooldown_widget_tiny, 1f, 1f, TitleStyle.EMOJI_ONLY), // 1x1
    WidgetLayout(R.layout.cooldown_widget_tall, 1f, 150f, TitleStyle.STACKED), // 1x2
    WidgetLayout(R.layout.cooldown_widget_wide, 110f, 1f, TitleStyle.INLINE), // 2x1 .. 4x1
    WidgetLayout(R.layout.cooldown_widget, 110f, 150f, TitleStyle.INLINE), // 2x2, 3x2
    WidgetLayout(R.layout.cooldown_widget_large, 250f, 150f, TitleStyle.INLINE, showEnds = true), // 4x2+
)

private val DEFAULT_LAYOUT = LAYOUTS[3]

private fun layoutFor(widthDp: Float, heightDp: Float): WidgetLayout =
    LAYOUTS.filter { it.fits(widthDp, heightDp) }.maxByOrNull { it.area } ?: LAYOUTS.first()

/** Same widget, other starting sizes in the widget picker (see res/xml/cooldown_widget_info_*.xml). */
class CooldownWidgetTallProvider : CooldownWidgetProvider()
class CooldownWidgetLargeProvider : CooldownWidgetProvider()

open class CooldownWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, appWidgetIds: IntArray) {
        updateAll(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_REFRESH) updateAll(context) else super.onReceive(context, intent)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        // Resized: before Android 12 we pick the layout ourselves, so redraw.
        updateAll(context)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        val editor = prefs(context).edit()
        appWidgetIds.forEach { editor.remove(widgetKey(it)) }
        editor.apply()
    }

    override fun onDisabled(context: Context) {
        // Called per picker entry; keep refreshing while any Cooldown widget is left.
        if (allWidgetIds(context).isNotEmpty()) return
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.cancel(refreshIntent(context))
    }

    companion object {
        const val ACTION_REFRESH = "com.berkan.cooldown.REFRESH"
        private const val HALF_HOUR_MS = 1_800_000L

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = allWidgetIds(context)
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
                val format = cooldown?.let { if (it.display == "default") defaultFormat else it.display } ?: defaultFormat
                fun build(layout: WidgetLayout) = buildViews(context, layout, id, cooldownId, cooldown, format, now)

                val views = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    // The launcher switches between these by itself while resizing.
                    RemoteViews(LAYOUTS.associate { SizeF(it.minWidthDp, it.minHeightDp) to build(it) })
                } else {
                    build(currentLayout(manager, id))
                }
                manager.updateAppWidget(id, views)

                if (cooldown != null) {
                    val end = cooldown.currentCycle(now).second
                    if (end > now) {
                        nextRefresh = minOf(nextRefresh, end + 1000)
                        if (CooldownFormat.isFineGrained(now, end, format)) {
                            nextRefresh = minOf(nextRefresh, now + 60_000)
                        }
                    }
                }
            }

            if (ids.isNotEmpty()) scheduleRefresh(context, nextRefresh)
        }

        private val PROVIDERS = listOf(
            CooldownWidgetProvider::class.java,
            CooldownWidgetTallProvider::class.java,
            CooldownWidgetLargeProvider::class.java,
        )

        fun allWidgetIds(context: Context): IntArray {
            val manager = AppWidgetManager.getInstance(context)
            return PROVIDERS.flatMap { manager.getAppWidgetIds(ComponentName(context, it)).asList() }.toIntArray()
        }

        /** Before Android 12: portrait size is min width x max height. */
        private fun currentLayout(manager: AppWidgetManager, appWidgetId: Int): WidgetLayout {
            val options = manager.getAppWidgetOptions(appWidgetId)
            val w = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
            val h = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0)
            return if (w == 0 || h == 0) DEFAULT_LAYOUT else layoutFor(w.toFloat(), h.toFloat())
        }

        private fun buildViews(
            context: Context,
            layout: WidgetLayout,
            appWidgetId: Int,
            cooldownId: String?,
            cooldown: Cooldown?,
            format: String,
            now: Long,
        ): RemoteViews {
            val views = RemoteViews(context.packageName, layout.layoutId)

            if (cooldown == null) {
                views.setTextViewText(R.id.title, title(layout, "⏳", "Cooldown"))
                views.setTextViewText(R.id.value, if (cooldownId == null) "Tap" else "?")
                views.setTextViewText(R.id.label, if (cooldownId == null) "to choose a cooldown" else "not found — tap to choose")
                views.setViewVisibility(R.id.progress, View.GONE)
                if (layout.showEnds) views.setTextViewText(R.id.ends, "")
                views.setInt(R.id.bg, "setColorFilter", 0xFF6B6B6B.toInt())
                views.setOnClickPendingIntent(R.id.root, configIntent(context, appWidgetId))
                return views
            }

            val (start, end) = cooldown.currentCycle(now)
            val finished = end <= now
            views.setTextViewText(R.id.title, title(layout, cooldown.emoji, cooldown.name))
            if (finished) {
                views.setTextViewText(R.id.value, if (cooldown.repeats) "Ready" else "Done")
                val label = when {
                    cooldown.finishText.isNotBlank() -> cooldown.finishText
                    cooldown.repeats -> "tap to mark done"
                    else -> "🎉"
                }
                views.setTextViewText(R.id.label, label)
            } else {
                val (value, label) = CooldownFormat.remaining(now, end, format)
                views.setTextViewText(R.id.value, value)
                views.setTextViewText(R.id.label, label)
            }
            if (layout.showEnds) {
                val date = Instant.ofEpochMilli(end).atZone(ZoneId.systemDefault()).format(ENDS_FORMAT)
                views.setTextViewText(R.id.ends, if (finished) "Ended $date" else "Ends $date")
            }
            val total = (end - start).coerceAtLeast(1)
            val pct = (((now - start).toDouble() / total) * 100).toInt().coerceIn(0, 100)
            views.setViewVisibility(R.id.progress, View.VISIBLE)
            views.setProgressBar(R.id.progress, 100, pct, false)
            views.setInt(R.id.bg, "setColorFilter", cooldown.color)
            views.setOnClickPendingIntent(R.id.root, openAppIntent(context))
            return views
        }

        private fun title(layout: WidgetLayout, emoji: String, name: String) = when (layout.title) {
            TitleStyle.EMOJI_ONLY -> emoji
            TitleStyle.STACKED -> "$emoji\n$name"
            TitleStyle.INLINE -> "$emoji $name"
        }

        private val ENDS_FORMAT = DateTimeFormatter.ofPattern("EEE, d MMM · HH:mm", Locale.getDefault())

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
