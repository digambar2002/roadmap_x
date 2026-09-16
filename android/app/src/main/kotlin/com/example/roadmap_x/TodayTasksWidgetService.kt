package com.example.roadmap_x

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray

class TodayTasksWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return TodayTasksRemoteViewsFactory(applicationContext)
    }
}

private data class TaskWidgetItem(
    val id: Long,
    val title: String,
    val goalTitle: String,
    val isOverdue: Boolean,
    val isDueToday: Boolean,
    val dueDateFormatted: String
)

class TodayTasksRemoteViewsFactory(private val context: Context) :
    RemoteViewsService.RemoteViewsFactory {

    private val taskList = mutableListOf<TaskWidgetItem>()

    override fun onCreate() {
        loadTasks()
    }

    override fun onDataSetChanged() {
        loadTasks()
    }

    private fun loadTasks() {
        taskList.clear()
        try {
            val widgetData = HomeWidgetPlugin.getData(context)
            val jsonString = widgetData.getString("tasks_json", "[]") ?: "[]"
            val jsonArray = JSONArray(jsonString)
            for (i in 0 until jsonArray.length()) {
                val obj = jsonArray.getJSONObject(i)
                taskList.add(
                    TaskWidgetItem(
                        id = obj.optLong("id", 0L),
                        title = obj.optString("title", "Untitled Task"),
                        goalTitle = obj.optString("goalTitle", ""),
                        isOverdue = obj.optBoolean("isOverdue", false),
                        isDueToday = obj.optBoolean("isDueToday", false),
                        dueDateFormatted = obj.optString("dueDateFormatted", "")
                    )
                )
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onDestroy() {
        taskList.clear()
    }

    override fun getCount(): Int = taskList.size

    override fun getViewAt(position: Int): RemoteViews? {
        if (position !in taskList.indices) return null
        val item = taskList[position]

        val views = RemoteViews(context.packageName, R.layout.widget_task_item)
        views.setTextViewText(R.id.task_item_title, item.title)

        // Goal Title / Tag
        if (item.goalTitle.isNotEmpty()) {
            views.setTextViewText(R.id.task_item_goal, item.goalTitle)
            views.setViewVisibility(R.id.task_item_goal, View.VISIBLE)
        } else {
            views.setViewVisibility(R.id.task_item_goal, View.GONE)
        }

        // Status Badge
        when {
            item.isOverdue -> {
                views.setTextViewText(R.id.task_item_badge, "Overdue")
                views.setInt(R.id.task_item_badge, "setBackgroundResource", R.drawable.widget_badge_overdue)
                views.setTextColor(R.id.task_item_badge, Color.parseColor("#FFE4E6"))
                views.setViewVisibility(R.id.task_item_badge, View.VISIBLE)
            }
            item.isDueToday -> {
                views.setTextViewText(R.id.task_item_badge, "Today")
                views.setInt(R.id.task_item_badge, "setBackgroundResource", R.drawable.widget_badge_today)
                views.setTextColor(R.id.task_item_badge, Color.parseColor("#E0F2FE"))
                views.setViewVisibility(R.id.task_item_badge, View.VISIBLE)
            }
            item.dueDateFormatted.isNotEmpty() -> {
                views.setTextViewText(R.id.task_item_badge, item.dueDateFormatted)
                views.setInt(R.id.task_item_badge, "setBackgroundResource", R.drawable.widget_badge_glass)
                views.setTextColor(R.id.task_item_badge, Color.parseColor("#C7D2FE"))
                views.setViewVisibility(R.id.task_item_badge, View.VISIBLE)
            }
            else -> {
                views.setViewVisibility(R.id.task_item_badge, View.GONE)
            }
        }

        // 1. Fill-in intent for Circle Check Button -> complete task
        val completeIntent = Intent().apply {
            action = TodayTasksWidgetProvider.ACTION_COMPLETE_TASK
            putExtra(TodayTasksWidgetProvider.EXTRA_TASK_ID, item.id)
        }
        views.setOnClickFillInIntent(R.id.task_item_check_btn, completeIntent)

        // 2. Fill-in intent for Task Body -> open app to today view
        val openIntent = Intent().apply {
            action = TodayTasksWidgetProvider.ACTION_OPEN_TASK
            putExtra(TodayTasksWidgetProvider.EXTRA_TASK_ID, item.id)
        }
        views.setOnClickFillInIntent(R.id.task_item_content, openIntent)

        return views
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long {
        return if (position in taskList.indices) taskList[position].id else position.toLong()
    }

    override fun hasStableIds(): Boolean = true
}
