package app.sinapsis

import android.content.Context
import android.os.Build
import android.provider.Settings

/**
 * El encendido del teléfono: el contador de arranques del sistema
 * (`Settings.Global.BOOT_COUNT`), que sube en uno cada vez que el teléfono
 * arranca. Sin permisos.
 *
 * **Es el único criterio de «la bóveda está abierta en este encendido»**, y
 * por eso vive en un solo lugar:
 * - la bóveda (Dart, `DeviceBoot` y `VaultRepositoryImpl`) lo pide por el
 *   canal `app.sinapsis/device_boot` ([SinapsisEngine]): al abrirse anota el
 *   de ahora y, al abrir la app, entra sin la clave si es el mismo;
 * - «Seguir escuchando» ([HomeWidgets.continueListeningShown]) lo compara,
 *   con la app muerta, con el encendido en que Dart le dijo que la bóveda
 *   estaba abierta: reiniciado el teléfono, ya no es el mismo y oculta el
 *   título, como la bóveda vuelve a pedir la clave (F47, paso 7a-bis).
 *
 * Del lado de Dart el encendido es este número como texto decimal
 * (`androidDeviceBoot`): [id] lo escribe igual.
 */
object DeviceBoot {
    /**
     * El contador de arranques, o `null` antes de Android 7, que no lo lleva.
     * Si el sistema no lo da, el error sube: la bóveda decide pedir la clave,
     * y el widget, ocultar.
     */
    fun count(context: Context): Int? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return null
        return Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT)
    }

    /**
     * El encendido de ahora como lo ve Dart —el contador en texto—, o `null`
     * si no se puede saber: ante la duda, quien lo usa oculta.
     */
    fun id(context: Context): String? = runCatching { count(context)?.toString() }.getOrNull()
}
