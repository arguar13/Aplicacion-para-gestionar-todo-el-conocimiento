package app.sinapsis

import android.app.ActivityManager
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Los ajustes del sistema que deciden si Sinapsis puede seguir trabajando
 * con la app cerrada (F29): el canal `app.sinapsis/background_settings`, que
 * usa la ayuda "Que siga con la app cerrada" del lado Dart.
 *
 * Android deja que el trabajo siga con la app cerrada, pero varias marcas lo
 * matan igual. En Xiaomi (MIUI y HyperOS, también Redmi y POCO) deslizar la
 * app la cierra del todo salvo que tenga **"Inicio automático"** y el ahorro
 * de batería en **"Sin restricciones"**. Ninguna app puede activarlos sola:
 * solo llevar a la persona a la pantalla justa.
 *
 * Por eso se prueban primero las pantallas propias de Xiaomi —que no son
 * parte de Android y cambian entre versiones— y, si no están o no se dejan
 * abrir, la ficha de la app en los ajustes, que existe en todo Android: desde
 * ahí, "Batería" lleva a "Sin restricciones" (Android 12 en adelante). Se
 * abren directamente, sin preguntar antes si existen: desde Android 11 la app
 * no ve los paquetes de otros, y preguntar diría que no aunque estén.
 */
class BackgroundSettingsChannel(private val context: Context) : MethodChannel.MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> result.success(status())
            "openAutostart" -> result.success(openAutostart())
            "openBattery" -> result.success(openBattery())
            else -> result.notImplemented()
        }
    }

    /**
     * Lo que se puede saber sin preguntarle a la persona: si es un Xiaomi, y
     * si Android ya no le aplica ahorro de batería a Sinapsis. "Inicio
     * automático" no se puede leer: Xiaomi no lo publica.
     */
    private fun status(): Map<String, Any?> {
        val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val activities = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        return mapOf(
            "xiaomi" to isXiaomi(),
            "batteryUnrestricted" to power.isIgnoringBatteryOptimizations(context.packageName),
            "backgroundRestricted" to
                (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && activities.isBackgroundRestricted),
        )
    }

    /**
     * Abre "Inicio automático" de Xiaomi; si no se puede, la ficha de la app.
     * Devuelve qué se abrió —`autostart`, `app_details`— o `null`.
     */
    private fun openAutostart(): String? {
        if (isXiaomi()) {
            val candidates = listOf(
                Intent().setComponent(
                    ComponentName(
                        "com.miui.securitycenter",
                        "com.miui.permcenter.autostart.AutoStartManagementActivity",
                    ),
                ),
                Intent("miui.intent.action.OP_AUTO_START").addCategory(Intent.CATEGORY_DEFAULT),
            )
            if (candidates.any(::launch)) return OPENED_AUTOSTART
        }
        return if (launch(appDetails())) OPENED_APP_DETAILS else null
    }

    /**
     * Abre el ahorro de batería de Sinapsis: en Xiaomi, su pantalla por app
     * ("Sin restricciones"); si no, la ficha de la app ("Batería"), y si
     * tampoco, la lista de optimización de batería de Android. Devuelve qué
     * se abrió —`battery`, `app_details`, `battery_list`— o `null`.
     */
    private fun openBattery(): String? {
        if (isXiaomi()) {
            val label = context.applicationInfo.loadLabel(context.packageManager).toString()
            val perApp = Intent()
                .setComponent(
                    ComponentName(
                        "com.miui.powerkeeper",
                        "com.miui.powerkeeper.ui.HiddenAppsConfigActivity",
                    ),
                )
                .putExtra("package_name", context.packageName)
                .putExtra("package_label", label)
            if (launch(perApp)) return OPENED_BATTERY
        }
        if (launch(appDetails())) return OPENED_APP_DETAILS
        return if (launch(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))) {
            OPENED_BATTERY_LIST
        } else {
            null
        }
    }

    private fun appDetails() = Intent(
        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
        Uri.fromParts("package", context.packageName, null),
    )

    /**
     * Abre [intent] desde la actividad, para que "atrás" vuelva a la app; si
     * no hay ninguna a la vista, como tarea nueva. `false` si no existe o el
     * sistema no la deja abrir —las de Xiaomi pueden no estar exportadas en
     * otra versión—.
     */
    private fun launch(intent: Intent): Boolean = try {
        val activity = SinapsisEngine.currentActivity()
        if (activity != null) {
            activity.startActivity(intent)
        } else {
            context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
        true
    } catch (e: ActivityNotFoundException) {
        false
    } catch (e: SecurityException) {
        Log.i(TAG, "El sistema no deja abrir ${intent.component ?: intent.action}", e)
        false
    }

    private fun isXiaomi(): Boolean =
        XIAOMI_BRANDS.any {
            Build.MANUFACTURER.equals(it, ignoreCase = true) || Build.BRAND.equals(it, ignoreCase = true)
        }

    companion object {
        const val CHANNEL = "app.sinapsis/background_settings"
        private const val TAG = "BackgroundSettings"
        private val XIAOMI_BRANDS = listOf("xiaomi", "redmi", "poco")

        private const val OPENED_AUTOSTART = "autostart"
        private const val OPENED_BATTERY = "battery"
        private const val OPENED_APP_DETAILS = "app_details"
        private const val OPENED_BATTERY_LIST = "battery_list"
    }
}
