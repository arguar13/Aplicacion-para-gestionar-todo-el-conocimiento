package app.sinapsis

import android.app.ActivityOptions
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.view.View
import android.widget.RemoteViews

/**
 * Los widgets de la pantalla de inicio (F47, paso 7, decisión G): cómo se
 * dibuja cada uno con lo que la app dejó en sus preferencias, y lo que hace
 * un toque.
 *
 * Lo que muestran lo guarda Dart con `home_widget` (`AndroidHomeScreenWidgets`),
 * que además le pide al sistema que los vuelva a dibujar. Las claves de acá
 * son las de allá: cambiar una es cambiar las dos.
 *
 * Un toque abre la app con [EXTRA_OPEN] y el nombre del widget, sin ninguna
 * dirección en el intent: Flutter mandaría una dirección como ruta, y adónde
 * llevar lo decide Dart (`HomeWidgetsBinding`). Ver [HomeWidgetsChannel].
 */
object HomeWidgets {
    /** El nombre del widget tocado, en el intent que abre la app. */
    const val EXTRA_OPEN = "app.sinapsis.extra.HOME_WIDGET_OPEN"
    private const val ACTION_OPEN = "app.sinapsis.action.HOME_WIDGET_OPEN"

    /** Los nombres de los widgets, los de `HomeWidgetKind` en Dart. */
    const val DUE_TODAY = "dueToday"
    const val QUICK_CAPTURE = "quickCapture"
    const val CONTINUE_LISTENING = "continueListening"

    private const val DUE_TODAY_COUNT = "due_today_count"
    private const val DUE_TODAY_VALID_UNTIL = "due_today_valid_until"
    private const val CONTINUE_LISTENING_TITLE = "continue_listening_title"
    private const val CONTINUE_LISTENING_SHOW_LOCKED = "continue_listening_show_locked"
    private const val CONTINUE_LISTENING_OPEN_BOOT = "continue_listening_open_boot"

    /**
     * «Para hoy»: la cifra que contó la app, mientras sea de hoy. Pasado el
     * día de estudio en que se contó —o si todavía no se contó nada—, no
     * repite una cifra vieja: invita a tocar para ver la de hoy.
     */
    fun dueTodayViews(context: Context, data: SharedPreferences): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.home_widget_due_today)
        val count = (data.all[DUE_TODAY_COUNT] as? Number)?.toInt()
        val validUntil = (data.all[DUE_TODAY_VALID_UNTIL] as? Number)?.toLong()
        val fresh = count != null && validUntil != null &&
            System.currentTimeMillis() < validUntil
        if (fresh && count!! > 0) {
            views.setViewVisibility(R.id.home_widget_due_today_count, View.VISIBLE)
            views.setTextViewText(R.id.home_widget_due_today_count, count.toString())
            views.setTextViewText(
                R.id.home_widget_due_today_label,
                context.resources.getQuantityString(R.plurals.home_widget_due_today_cards, count),
            )
        } else {
            views.setViewVisibility(R.id.home_widget_due_today_count, View.GONE)
            views.setTextViewText(
                R.id.home_widget_due_today_label,
                context.getString(
                    if (fresh) R.string.home_widget_due_today_none
                    else R.string.home_widget_due_today_unknown,
                ),
            )
        }
        views.setOnClickPendingIntent(android.R.id.background, openIntent(context, DUE_TODAY))
        return views
    }

    /** «Guardar rápido»: siempre igual; solo lleva su toque. */
    fun quickCaptureViews(context: Context): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.home_widget_quick_capture)
        views.setOnClickPendingIntent(android.R.id.background, openIntent(context, QUICK_CAPTURE))
        return views
    }

    /**
     * «Seguir escuchando»: el título de lo último que se escuchó, o —si la
     * bóveda no está abierta en este encendido y la persona no eligió dejarlo
     * a la vista— un texto que no dice qué (F47, paso 7a-bis). Lo decide
     * [continueListeningShown] con el encendido de ahora, así que vale también
     * cuando Android lo dibuja con la app muerta: al reiniciar el teléfono, o
     * al pedírselo la pantalla de inicio.
     */
    fun continueListeningViews(context: Context, data: SharedPreferences): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.home_widget_continue_listening)
        val values = data.all
        val title = values[CONTINUE_LISTENING_TITLE] as? String
        val shown = continueListeningShown(
            title = title,
            showWhileLocked = values[CONTINUE_LISTENING_SHOW_LOCKED] as? Boolean == true,
            openBoot = values[CONTINUE_LISTENING_OPEN_BOOT] as? String,
            currentBoot = DeviceBoot.id(context),
        )
        views.setTextViewText(
            R.id.home_widget_continue_listening_title,
            when (shown) {
                ContinueListeningShown.TITLE -> title
                ContinueListeningShown.PROTECTED ->
                    context.getString(R.string.home_widget_continue_protected)
                ContinueListeningShown.NOTHING ->
                    context.getString(R.string.home_widget_continue_empty)
            },
        )
        views.setOnClickPendingIntent(
            android.R.id.background,
            openIntent(context, CONTINUE_LISTENING),
        )
        return views
    }

    /** Lo que se ve en «Seguir escuchando». */
    enum class ContinueListeningShown {
        /** «Todavía no escuchaste nada». */
        NOTHING,

        /** El título de lo último que se escuchó. */
        TITLE,

        /** «Protegido: tocá para seguir», sin el título. */
        PROTECTED,
    }

    /**
     * Qué muestra «Seguir escuchando» (F47, paso 7a-bis). Una función pura,
     * sin Android, para que la regla se lea entera en un lugar; es **la misma
     * de `ContinueListeningDisplay.shownIn`** en Dart, que la prueba (cambiar
     * una es cambiar las dos):
     *
     * - sin [title] —nada escuchado—, [ContinueListeningShown.NOTHING];
     * - si la persona eligió dejarlo a la vista con la bóveda cerrada
     *   ([showWhileLocked], Ajustes › Widgets), el título siempre;
     * - si no, el título solo si la bóveda está abierta en este mismo
     *   encendido: [openBoot] —el encendido en que Dart dijo que estaba
     *   abierta— igual a [currentBoot] —el de ahora, ver [DeviceBoot]—. Es el
     *   criterio de la bóveda: reiniciado el teléfono, ella vuelve a pedir la
     *   clave y el widget oculta el título, aunque la app no haya vuelto a
     *   andar;
     * - en cualquier otro caso —la bóveda cerrada, un encendido que no se
     *   sabe, lo que dejó una versión anterior sin estas claves—,
     *   [ContinueListeningShown.PROTECTED]: ante la duda, se oculta.
     */
    fun continueListeningShown(
        title: String?,
        showWhileLocked: Boolean,
        openBoot: String?,
        currentBoot: String?,
    ): ContinueListeningShown {
        if (title.isNullOrBlank()) return ContinueListeningShown.NOTHING
        if (showWhileLocked) return ContinueListeningShown.TITLE
        if (openBoot != null && currentBoot != null && openBoot == currentBoot) {
            return ContinueListeningShown.TITLE
        }
        return ContinueListeningShown.PROTECTED
    }

    /**
     * Lo que abre la app al tocar el widget [name]. Uno por widget —el código
     * del pedido es distinto—, para que el sistema no los confunda.
     *
     * Desde Android 15 quien crea el intent tiene que dejar que abra una
     * actividad aunque la app no esté a la vista: es lo que arregló
     * `home_widget` cuando abrir la app desde un widget fallaba ahí.
     */
    @Suppress("DEPRECATION")
    private fun openIntent(context: Context, name: String): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .setAction(ACTION_OPEN)
            .putExtra(EXTRA_OPEN, name)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val requestCode = REQUEST_CODES.getValue(name)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            return PendingIntent.getActivity(context, requestCode, intent, flags)
        }
        val options = ActivityOptions.makeBasic().setPendingIntentCreatorBackgroundActivityStartMode(
            ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED,
        )
        return PendingIntent.getActivity(context, requestCode, intent, flags, options.toBundle())
    }

    private val REQUEST_CODES = mapOf(
        DUE_TODAY to 4701,
        QUICK_CAPTURE to 4702,
        CONTINUE_LISTENING to 4703,
    )
}
