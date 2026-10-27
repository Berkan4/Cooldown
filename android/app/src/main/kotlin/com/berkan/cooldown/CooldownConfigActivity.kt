package com.berkan.cooldown

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import android.widget.ArrayAdapter
import android.widget.ListView
import android.widget.Toast

/** Shown when a widget is added (or reconfigured): pick which cooldown it shows. */
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
            CooldownWidgetProvider.updateAll(this)
            setResult(RESULT_OK, resultIntent())
            finish()
        }
        setContentView(list)
    }

    private fun resultIntent() = Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
}
