package com.rafa.notas

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.File

/**
 * Widget de calendario redimensionable. La app de Flutter dibuja tres
 * versiones como imagen y aquí se muestra la que encaja con el tamaño:
 *  - S (2x2): solo el mes            -> calendario_img_s
 *  - M (4x2): mes + tareas al lado   -> calendario_img_m
 *  - L (4x4): mes + lista de tareas  -> calendario_img_l
 * Debajo hay un fondo redondeado sólido con el color del tema, para que
 * nunca se vea transparente aunque la imagen no ocupe toda la celda.
 * Al tocarlo se abre la app en el calendario.
 */
class CalendarioWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { id -> render(context, appWidgetManager, id, widgetData) }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        render(context, appWidgetManager, appWidgetId, HomeWidgetPlugin.getData(context))
    }

    private fun sizeKey(manager: AppWidgetManager, id: Int): String {
        val o = manager.getAppWidgetOptions(id)
        // Ancho mínimo (vertical) y alto máximo (vertical), en dp.
        val w = o.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 250)
        val h = o.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 110)
        return when {
            w < 200 -> "calendario_img_s"
            h < 230 -> "calendario_img_m"
            else -> "calendario_img_l"
        }
    }

    private fun render(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        data: SharedPreferences
    ) {
        val views = RemoteViews(context.packageName, R.layout.calendario_widget)

        // Color de fondo del tema actual (lo guarda la app junto a las imágenes).
        if (data.contains("calendario_bg")) {
            // Dart guarda los colores opacos (0xFF......) como Long.
            val bg = try {
                data.getLong("calendario_bg", 0L).toInt()
            } catch (e: ClassCastException) {
                data.getInt("calendario_bg", 0)
            }
            views.setInt(R.id.calendario_bg, "setColorFilter", bg)
        }

        val key = sizeKey(manager, id)
        val path = data.getString(key, null) ?: data.getString("calendario_img", null)
        val bitmap = path?.let { p -> if (File(p).exists()) BitmapFactory.decodeFile(p) else null }
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
        manager.updateAppWidget(id, views)
    }
}
