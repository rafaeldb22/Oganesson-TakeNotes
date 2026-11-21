package com.rafa.notas

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.content.res.Configuration
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Accesos rápidos (4x1): nueva nota, calendario, red de notas y buscar.
 * Cada botón abre la app directamente en ese sitio. Los iconos toman el
 * color de acento del tema elegido en la app.
 */
class AccionesWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val noche = (context.resources.configuration.uiMode and
                Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
        val sufijo = if (noche) "oscuro" else "claro"
        val acento = if (widgetData.contains("acento_$sufijo")) {
            try {
                widgetData.getLong("acento_$sufijo", 0L).toInt()
            } catch (e: ClassCastException) {
                widgetData.getInt("acento_$sufijo", 0)
            }
        } else null

        val botones = listOf(
            Triple(R.id.accion_nueva, R.id.accion_nueva_icono, "notas://nueva"),
            Triple(R.id.accion_calendario, R.id.accion_calendario_icono, "notas://calendario"),
            Triple(R.id.accion_red, R.id.accion_red_icono, "notas://red"),
            Triple(R.id.accion_buscar, R.id.accion_buscar_icono, "notas://buscar"),
        )
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.acciones_widget)
            botones.forEachIndexed { i, (boton, icono, uri) ->
                if (acento != null) views.setInt(icono, "setColorFilter", acento)
                val intent = HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, Uri.parse(uri)
                )
                views.setOnClickPendingIntent(boton, intent)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
