package com.example.roadmap_x

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray

class TodayTasksWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
        super.onUpdate(context, appWidgetManager, appWidgetIds)
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action == ACTION_COMPLETE_TASK) {
            val taskId = intent.getLongExtra(EXTRA_TASK_ID, -1L)
            if (taskId != -1L) {
                handleCompleteTask(context, taskId)
            }
            return
        } else if (action == ACTION_OPEN_TASK) {
            val taskId = intent.getLongExtra(EXTRA_TASK_ID, -1L)
            val launchIntent = Intent(context, MainActivity::class.java).apply {
                this.action = Intent.ACTION_VIEW
                data = Uri.parse("roadmapx://roadmapx/today?taskId=$taskId")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            context.startActivity(launchIntent)
            return
        }

        super.onReceive(context, intent)
        val appWidgetManager = AppWidgetManager.getInstance(context)
        val thisWidget = ComponentName(context, TodayTasksWidgetProvider::class.java)
        val appWidgetIds = appWidgetManager.getAppWidgetIds(thisWidget)
        if (appWidgetIds != null && appWidgetIds.isNotEmpty()) {
            for (appWidgetId in appWidgetIds) {
                updateAppWidget(context, appWidgetManager, appWidgetId)
            }
            appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetIds, R.id.widget_task_list)
        }
    }

    private fun handleCompleteTask(context: Context, taskId: Long) {
        try {
            val widgetData = HomeWidgetPlugin.getData(context)
            val jsonString = widgetData.getString("tasks_json", "[]") ?: "[]"
            val originalArray = JSONArray(jsonString)
            val newArray = JSONArray()
            for (i in 0 until originalArray.length()) {
                val obj = originalArray.getJSONObject(i)
                if (obj.optLong("id", -1L) != taskId) {
                    newArray.put(obj)
                }
            }
            val newCount = newArray.length()
            widgetData.edit()
                .putString("tasks_json", newArray.toString())
                .putInt("task_count", newCount)
                .apply()

            // Save to pending completions so Flutter syncs DB if not running
            val pendingStr = widgetData.getString("pending_completed_task_ids", "[]") ?: "[]"
            val pendingArray = JSONArray(pendingStr)
            pendingArray.put(taskId)
            widgetData.edit().putString("pending_completed_task_ids", pendingArray.toString()).apply()

            // Trigger background callback to update database in background
            try {
                val bgIntent = HomeWidgetBackgroundIntent.getBroadcast(
                    context,
                    Uri.parse("roadmapx://complete?taskId=$taskId")
                )
                bgIntent.send()
            } catch (e: Exception) {
                e.printStackTrace()
            }

            // Immediately refresh the widget RemoteViews
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val thisWidget = ComponentName(context, TodayTasksWidgetProvider::class.java)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(thisWidget)
            if (appWidgetIds != null && appWidgetIds.isNotEmpty()) {
                for (id in appWidgetIds) {
                    updateAppWidget(context, appWidgetManager, id)
                }
                appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetIds, R.id.widget_task_list)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    companion object {
        const val ACTION_COMPLETE_TASK = "com.example.roadmap_x.ACTION_COMPLETE_TASK"
        const val ACTION_OPEN_TASK = "com.example.roadmap_x.ACTION_OPEN_TASK"
        const val EXTRA_TASK_ID = "com.example.roadmap_x.EXTRA_TASK_ID"

        fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val views = RemoteViews(context.packageName, R.layout.widget_today_tasks)
            val widgetData = HomeWidgetPlugin.getData(context)

            val taskCount = widgetData.getInt("task_count", 0)
            val dateFormatted = widgetData.getString("date_formatted", "Today") ?: "Today"

            // Header labels
            views.setTextViewText(R.id.widget_date_text, dateFormatted)
            val countText = when (taskCount) {
                0 -> "All Clear ✨"
                1 -> "1 task"
                else -> "$taskCount tasks"
            }
            views.setTextViewText(R.id.widget_count_text, countText)

            // Bind RemoteViewsService to the ListView
            val serviceIntent = Intent(context, TodayTasksWidgetService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
            }
            views.setRemoteAdapter(R.id.widget_task_list, serviceIntent)
            views.setEmptyView(R.id.widget_task_list, R.id.widget_empty_view)

            // Header and button clicks (opens app at /today)
            val launchUri = Uri.parse("roadmapx://roadmapx/today")
            val launchIntent = Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                data = launchUri
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val headerFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            val headerPendingIntent = PendingIntent.getActivity(
                context,
                0,
                launchIntent,
                headerFlags
            )

            views.setOnClickPendingIntent(R.id.widget_header, headerPendingIntent)
            views.setOnClickPendingIntent(R.id.widget_action_btn, headerPendingIntent)
            views.setOnClickPendingIntent(R.id.widget_empty_view, headerPendingIntent)

            // Broadcast pending intent template for ListView items
            val templateIntent = Intent(context, TodayTasksWidgetProvider::class.java)
            val templateFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            val itemPendingIntent = PendingIntent.getBroadcast(
                context,
                100,
                templateIntent,
                templateFlags
            )
            views.setPendingIntentTemplate(R.id.widget_task_list, itemPendingIntent)

            // Update widget and notify list
            appWidgetManager.updateAppWidget(appWidgetId, views)
            appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.widget_task_list)
        }
    }
}
