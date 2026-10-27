package com.berkan.cooldown

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.ImageView
import android.widget.ListView
import android.widget.SeekBar
import android.widget.TextView
import android.widget.Toast
import kotlin.math.roundToInt

/**
 * Opened when a widget is added and from the widget's settings (long-press).
 * A new widget (or one whose cooldown was deleted) picks which cooldown it shows;
 * an existing one gets its background transparency setting instead.
 */
class CooldownConfigActivity : Activity() {

    private var appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        appWidgetId = intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID

        // If the user backs out, the widget is not added.
        setResult(RESULT_CANCELED, resultIntent())
        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        val cooldowns = Cooldown.loadAll(this)
        val current = cooldowns.firstOrNull { it.id == prefs(this).getString(widgetKey(appWidgetId), null) }
        if (current != null) showSettings(current) else showPicker(cooldowns)
    }

    private fun showPicker(cooldowns: List<Cooldown>) {
        if (cooldowns.isEmpty()) {
            Toast.makeText(this, "Create a cooldown in the app first", Toast.LENGTH_LONG).show()
            startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            finish()
            return
        }

        title = "Show which cooldown?"
        val list = ListView(this)
        list.adapter = ArrayAdapter(
            this,
            android.R.layout.simple_list_item_1,
            cooldowns.map { "${it.emoji}  ${it.name}" },
        )
        list.setOnItemClickListener { _, _, position, _ ->
            prefs(this).edit().putString(widgetKey(appWidgetId), cooldowns[position].id).apply()
            done()
        }
        setContentView(list)
    }

    private fun showSettings(cooldown: Cooldown) {
        title = "Widget background"
        setContentView(R.layout.widget_settings)
        val seek = findViewById<SeekBar>(R.id.opacity)
        val label = findViewById<TextView>(R.id.opacity_label)
        val previewBg = findViewById<ImageView>(R.id.preview_bg)
        val previewText = findViewById<TextView>(R.id.preview_text)

        findViewById<TextView>(R.id.settings_name).text = "${cooldown.emoji}  ${cooldown.name}"
        previewText.text = "${cooldown.emoji} ${cooldown.name}"
        previewBg.setColorFilter(cooldown.color)

        fun show(steps: Int) {
            val opacity = steps / 20.0
            label.text = "Background: ${(opacity * 100).roundToInt()}%  (0% = fully transparent)"
            previewBg.imageAlpha = (opacity * 255).roundToInt()
            val darkText = opacity >= 0.5 && Color.luminance(cooldown.color) > 0.6f
            previewText.setTextColor(if (darkText) CooldownWidgetProvider.TEXT_DARK else Color.WHITE)
        }

        seek.progress = (cooldown.widgetOpacity * 20).roundToInt()
        show(seek.progress)
        seek.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(bar: SeekBar, progress: Int, fromUser: Boolean) = show(progress)
            override fun onStartTrackingTouch(bar: SeekBar) {}
            override fun onStopTrackingTouch(bar: SeekBar) {}
        })

        findViewById<Button>(R.id.done).setOnClickListener {
            // Saved on the cooldown itself: the app's editor shows the same value.
            saveWidgetOpacity(this, cooldown.id, seek.progress / 20.0)
            done()
        }
    }

    private fun done() {
        CooldownWidgetProvider.updateAll(this)
        setResult(RESULT_OK, resultIntent())
        finish()
    }

    private fun resultIntent() = Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
}
