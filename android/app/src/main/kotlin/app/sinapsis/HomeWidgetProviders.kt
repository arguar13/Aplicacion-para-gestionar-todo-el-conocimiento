package app.sinapsis

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
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

/**
 * «Seguir escuchando».
 *
 * Además de lo que le pide la pantalla de inicio, se vuelve a dibujar apenas
 * arranca el teléfono (F47, paso 7a-bis): la bóveda acaba de quedar cerrada,
 * y si la persona no eligió dejar el título a la vista, el widget tiene que
 * ocultarlo sin esperar a que se abra la app. Lo que decide es el encendido
 * (ver [HomeWidgets.continueListeningShown]); esto solo asegura que se
 * dibuje enseguida, aunque la pantalla de inicio no lo pida.
 */
class ContinueListeningWidget : HomeWidgetProvider() {
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(
            ComponentName(context, ContinueListeningWidget::class.java),
        )
        if (ids.isNotEmpty()) onUpdate(context, manager, ids)
    }

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
