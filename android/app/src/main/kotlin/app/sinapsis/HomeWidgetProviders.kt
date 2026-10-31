package app.sinapsis

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import es.antonborri.home_widget.HomeWidgetProvider

// Los tres widgets de la pantalla de inicio (F47, paso 7). Cada uno se
// dibuja con lo que la app dejó en las preferencias de `home_widget`, que el
// paquete le pasa en `widgetData`: ver `HomeWidgets`.

/** «Para hoy · N tarjetas». */
class DueTodayWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val views = HomeWidgets.dueTodayViews(context, widgetData)
        appWidgetIds.forEach { appWidgetManager.updateAppWidget(it, views) }
    }
}

/** «Guardar rápido». */
class QuickCaptureWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val views = HomeWidgets.quickCaptureViews(context)
        appWidgetIds.forEach { appWidgetManager.updateAppWidget(it, views) }
    }
}

/** «Seguir escuchando». */
class ContinueListeningWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val views = HomeWidgets.continueListeningViews(context, widgetData)
        appWidgetIds.forEach { appWidgetManager.updateAppWidget(it, views) }
    }
}
