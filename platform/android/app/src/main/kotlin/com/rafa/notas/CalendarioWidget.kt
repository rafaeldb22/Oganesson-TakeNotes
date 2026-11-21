package com.rafa.notas

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.File

/**
 * Widget 4x2 con el calendario del mes y las tareas por fecha límite.
 * La app de Flutter dibuja el contenido como imagen (calendario_img) y
 * aquí solo se muestra. Al tocarlo se abre la app en el calendario.
 */
class CalendarioWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.calendario_widget)
            val path = widgetData.getString("calendario_img", null)
            val bitmap = path?.let { p ->
                if (File(p).exists()) BitmapFactory.decodeFile(p) else null
            }
            if (bitmap != null) {
                views.setImageViewBitmap(R.id.calendario_img, bitmap)
                views.setViewVisibility(R.id.calendario_img, View.VISIBLE)
                views.setViewVisibility(R.id.calendario_vacio, View.GONE)
            } else {
                views.setViewVisibility(R.id.calendario_img, View.GONE)
                views.setViewVisibility(R.id.calendario_vacio, View.VISIBLE)
            }
            val abrir = HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java, Uri.parse("notas://calendario")
            )
            views.setOnClickPendingIntent(R.id.calendario_root, abrir)
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
