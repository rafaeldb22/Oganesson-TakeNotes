package com.rafa.notas

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Widget 2x2: muestra la última nota y un botón "Nueva nota" que abre la app
 * directamente en una nota vacía con el teclado listo.
 */
class NotasWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.notas_widget).apply {
                setTextViewText(
                    R.id.widget_titulo,
                    widgetData.getString("ultima_titulo", "Sin notas todavía")
                )
                setTextViewText(
                    R.id.widget_preview,
                    widgetData.getString("ultima_preview", "Toca «Nueva nota» para escribir")
                )
                setTextViewText(R.id.widget_total, widgetData.getString("total", ""))

                // Color del tema elegido en la app.
                val noche = (context.resources.configuration.uiMode and
                        Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
                val sufijo = if (noche) "oscuro" else "claro"
                if (widgetData.contains("acento_$sufijo")) {
                    val acento = widgetData.getLong("acento_$sufijo", 0L).toInt()
                    val texto = widgetData.getLong("texto_boton_$sufijo", 0xFFFFFFFF).toInt()
                    setTextColor(R.id.widget_label, acento)
                    setTextColor(R.id.widget_nueva, texto)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        setColorStateList(
                            R.id.widget_nueva, "setBackgroundTintList",
                            ColorStateList.valueOf(acento)
                        )
                    }
                }

                val abrir = HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, Uri.parse("notas://abrir")
                )
                setOnClickPendingIntent(R.id.widget_root, abrir)

                val nueva = HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, Uri.parse("notas://nueva")
                )
                setOnClickPendingIntent(R.id.widget_nueva, nueva)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
