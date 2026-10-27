package com.berkan.cooldown

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.temporal.ChronoUnit

/** Same file home_widget writes to from Dart. */
const val PREFS = "HomeWidgetPreferences"

fun prefs(context: Context): SharedPreferences =
    context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

fun widgetKey(appWidgetId: Int) = "widget_$appWidgetId"

/** Kotlin mirror of lib/models/cooldown.dart — keep the logic in sync. */
data class Cooldown(
    val id: String,
    val name: String,
    val emoji: String,
    val color: Int,
    val targetMs: Long,
    val startMs: Long,
    val repeatValue: Int,
    val repeatUnit: String,
    val waitForDone: Boolean,
    val display: String,
) {
    private val autoRepeats get() = repeatValue > 0 && !waitForDone
    val repeats get() = repeatValue > 0

    private fun zdt(ms: Long): ZonedDateTime =
        Instant.ofEpochMilli(ms).atZone(ZoneId.systemDefault())

    private fun occurrence(k: Long): ZonedDateTime {
        val anchor = zdt(targetMs)
        val n = repeatValue.toLong() * k
        return when (repeatUnit) {
            "hours" -> anchor.plusHours(n)
            "weeks" -> anchor.plusWeeks(n)
            "months" -> anchor.plusMonths(n)
            "years" -> anchor.plusYears(n)
            else -> anchor.plusDays(n)
        }
    }

    private fun approxIntervalMs(): Long {
        val h = 3_600_000L
        return repeatValue * when (repeatUnit) {
            "hours" -> h
            "weeks" -> 7 * 24 * h
            "months" -> 31 * 24 * h
            "years" -> 366 * 24 * h
            else -> 24 * h
        }
    }

    /** Returns (cycleStartMs, cycleEndMs) for the current cycle. */
    fun currentCycle(nowMs: Long): Pair<Long, Long> {
        if (!autoRepeats || targetMs > nowMs) return startMs to targetMs
        var k = maxOf(0L, (nowMs - targetMs) / approxIntervalMs() - 2)
        var end = occurrence(k).toInstant().toEpochMilli()
        while (end <= nowMs) {
            k++
            end = occurrence(k).toInstant().toEpochMilli()
        }
        val begin = if (k == 0L) startMs else occurrence(k - 1).toInstant().toEpochMilli()
        return begin to end
    }

    companion object {
        fun loadAll(context: Context): List<Cooldown> {
            val raw = prefs(context).getString("cooldowns", null) ?: return emptyList()
            return try {
                val arr = JSONArray(raw)
                (0 until arr.length()).map { i ->
                    val o = arr.getJSONObject(i)
                    Cooldown(
                        id = o.getString("id"),
                        name = o.optString("name", ""),
                        emoji = o.optString("emoji", "⏳"),
                        color = o.optLong("color", 0xFF4F7CACL).toInt(),
                        targetMs = o.getLong("targetMs"),
                        startMs = o.getLong("startMs"),
                        repeatValue = o.optInt("repeatValue", 0),
                        repeatUnit = o.optString("repeatUnit", "days"),
                        waitForDone = o.optBoolean("waitForDone", true),
                        display = o.optString("display", "default"),
                    )
                }
            } catch (e: Exception) {
                emptyList()
            }
        }
    }
}

/** Kotlin mirror of lib/utils/format.dart. Returns (value, label). */
object CooldownFormat {
    private fun hm(d: Duration): String {
        val h = d.toHours()
        val m = d.toMinutes() % 60
        return when {
            h > 0 -> "${h}h ${m}m"
            m > 0 -> "${m}m"
            else -> "<1m"
        }
    }

    private fun dhm(d: Duration): String {
        val days = d.toDays()
        val h = d.toHours() % 24
        val m = d.toMinutes() % 60
        return if (days > 0) "${days}d ${h}h ${m}m" else hm(d)
    }

    fun remaining(nowMs: Long, endMs: Long, format: String): Pair<String, String> {
        val left = Duration.ofMillis(endMs - nowMs)
        if (left.isNegative || left.isZero) return "0" to "ready"
        val zone = ZoneId.systemDefault()
        val calDays = ChronoUnit.DAYS.between(
            Instant.ofEpochMilli(nowMs).atZone(zone).toLocalDate(),
            Instant.ofEpochMilli(endMs).atZone(zone).toLocalDate(),
        )

        fun days(): Pair<String, String> =
            if (calDays >= 1) "$calDays" to (if (calDays == 1L) "day" else "days")
            else hm(left) to "left today"

        return when (format) {
            "weeks" -> if (calDays >= 7) {
                val w = calDays / 7
                val d = calDays % 7
                (if (d == 0L) "${w}w" else "${w}w ${d}d") to "left"
            } else days()
            "hours" -> if (left.toHours() >= 1) {
                "${left.toHours()}" to (if (left.toHours() == 1L) "hour" else "hours")
            } else (if (left.toMinutes() > 0) "${left.toMinutes()}" else "<1") to "min"
            "detailed" -> dhm(left) to "left"
            "auto" -> if (calDays >= 2) days() else dhm(left) to "left"
            else -> days()
        }
    }

    /** Whether this format changes more often than once a day. */
    fun isFineGrained(nowMs: Long, endMs: Long, format: String): Boolean {
        val left = endMs - nowMs
        val dayMs = 86_400_000L
        return when (format) {
            "hours", "detailed" -> true
            "auto" -> left < 3 * dayMs
            else -> left < 2 * dayMs
        }
    }
}
