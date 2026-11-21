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
 * Base de los widgets que la app de Flutter dibuja como imagen (Tareas,
 * Próxima tarea, Notas fijadas): fondo redondeado sólido con el color del
 * tema, la imagen que encaja con el tamaño actual (cambia al redimensionar)
 * y un toque que abre la app en el sitio adecuado.
 */
abstract class ImagenWidget : HomeWidgetProvider() {

    /** Clave de la imagen para un widget de [w]x[h] dp. */
    abstract fun imageKey(w: Int, h: Int): String

    /** Dirección que se abre al tocarlo (notas://…). */
    open fun clickUri(data: SharedPreferences): String = "notas://abrir"

    /** Texto mientras la app aún no ha dibujado el widget. */
    open val emptyText: String = "Abre Oganesson para cargar el widget"

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { render(context, appWidgetManager, it, widgetData) }
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

    private fun render(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        data: SharedPreferences
    ) {
        val views = RemoteViews(context.packageName, R.layout.imagen_widget)

        // Fondo con el color de tarjeta del tema (Dart lo guarda como Long).
        if (data.contains("calendario_bg")) {
            val bg = try {
                data.getLong("calendario_bg", 0L).toInt()
            } catch (e: ClassCastException) {
                data.getInt("calendario_bg", 0)
            }
            views.setInt(R.id.imagen_bg, "setColorFilter", bg)
        }

        val o = manager.getAppWidgetOptions(id)
        val w = o.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 250)
        val h = o.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 110)
        val path = data.getString(imageKey(w, h), null)
        val bitmap = path?.let { p -> if (File(p).exists()) BitmapFactory.decodeFile(p) else null }
        if (bitmap != null) {
            views.setImageViewBitmap(R.id.imagen_contenido, bitmap)
            views.setViewVisibility(R.id.imagen_contenido, View.VISIBLE)
            views.setViewVisibility(R.id.imagen_vacio, View.GONE)
        } else {
            views.setTextViewText(R.id.imagen_vacio, emptyText)
            views.setViewVisibility(R.id.imagen_contenido, View.GONE)
            views.setViewVisibility(R.id.imagen_vacio, View.VISIBLE)
        }
        val abrir = HomeWidgetLaunchIntent.getActivity(
            context, MainActivity::class.java, Uri.parse(clickUri(data))
        )
        views.setOnClickPendingIntent(R.id.imagen_root, abrir)
        manager.updateAppWidget(id, views)
    }
}

/** Tareas de hoy y próximas (2x2, 4x2 o 4x4). Abre el calendario. */
class TareasWidget : ImagenWidget() {
    override fun imageKey(w: Int, h: Int) = when {
        w < 200 -> "tareas_img_s"
        h < 230 -> "tareas_img_m"
        else -> "tareas_img_l"
    }

    override fun clickUri(data: SharedPreferences) = "notas://calendario"
}

/** La tarea que vence antes, con cuenta atrás. Abre esa nota. */
class ProximaWidget : ImagenWidget() {
    override fun imageKey(w: Int, h: Int) =
        if (h < 140) "proxima_img_w" else "proxima_img_s"

    override fun clickUri(data: SharedPreferences): String {
        val id = data.getString("proxima_id", null)
        return if (id.isNullOrEmpty()) "notas://calendario" else "notas://nota/$id"
    }
}

/** Notas fijadas (o recientes). Abre la app. */
class FijadasWidget : ImagenWidget() {
    override fun imageKey(w: Int, h: Int) =
        if (h < 230) "fijadas_img_m" else "fijadas_img_l"
}
