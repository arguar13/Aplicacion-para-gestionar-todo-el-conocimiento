package app.sinapsis

import android.app.DownloadManager
import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.os.Environment
import android.os.StatFs
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Las descargas de los modelos con el gestor del sistema (F29): el canal
 * `app.sinapsis/system_downloads`, que usa `SystemModelFileTransfer` del lado
 * Dart.
 *
 * `DownloadManager` baja en el proceso del sistema, no en el de la app: la
 * descarga sigue aunque se cierre la app —también si HyperOS la mata— o se
 * reinicie el teléfono, espera la red si se corta, retoma por rango y muestra
 * su propia notificación. Sigue las redirecciones de Hugging Face a su CDN
 * (hasta cinco, también las relativas) y, para retomar, le pide al CDN el
 * resto con el ETag que este dio —fuerte, comprobado el 2026-10-03—.
 *
 * Solo puede escribir en la carpeta propia de la app en el almacenamiento
 * compartido (`getExternalFilesDir`), no en la interna: los modelos bajados
 * así viven ahí.
 */
class SystemDownloadsChannel(private val context: Context) : MethodChannel.MethodCallHandler {
    private val manager: DownloadManager
        get() = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "directory" -> result.success(directory()?.absolutePath)
                "enqueue" -> enqueue(call, result)
                "query" -> result.success(query(call.idArgument()))
                "remove" -> {
                    manager.remove(call.idArgument())
                    result.success(null)
                }
                "freeBytes" -> result.success(
                    context.getExternalFilesDir(null)?.let { StatFs(it.path).availableBytes },
                )
                else -> result.notImplemented()
            }
        } catch (e: RuntimeException) {
            // El gestor deshabilitado o un pedido que no acepta: Dart lo
            // recibe como error de la descarga, nunca como la app caída.
            Log.w(TAG, "Descarga del sistema: ${call.method} falló", e)
            result.error("system_downloads", e.message ?: e.toString(), null)
        }
    }

    /**
     * La carpeta donde el sistema puede dejar los modelos, o `null` si no se
     * puede usar: el almacenamiento compartido sin montar, o el gestor de
     * descargas deshabilitado —se puede, desde los ajustes de apps del
     * sistema—. Sin ella, Dart baja dentro de la app, como antes.
     */
    private fun directory(): File? {
        if (Environment.getExternalStorageState() != Environment.MEDIA_MOUNTED) return null
        if (!managerWorks()) return null
        return context.getExternalFilesDir(null)
    }

    private fun managerWorks(): Boolean = try {
        manager.query(DownloadManager.Query().setFilterById(-1L))?.use { true } ?: false
    } catch (e: RuntimeException) {
        Log.w(TAG, "El gestor de descargas del sistema no está disponible", e)
        false
    }

    private fun enqueue(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url")
        val path = call.argument<String>("path")
        val base = context.getExternalFilesDir(null)
        if (url == null || path == null || base == null) {
            result.error("arguments", "Faltan url y path, o la carpeta de la app.", null)
            return
        }
        val destination = File(path).canonicalFile
        val root = base.canonicalFile
        if (!destination.path.startsWith(root.path + File.separator)) {
            result.error("arguments", "El destino tiene que estar dentro de $root.", null)
            return
        }
        destination.parentFile?.mkdirs()

        val model = context.getString(
            when (call.argument<String>("label")) {
                LABEL_RELATIONS_MODEL -> R.string.long_work_model_relations
                LABEL_TRANSCRIPTION_MODEL -> R.string.long_work_model_transcription
                else -> R.string.long_work_model_language
            },
        )
        val request = DownloadManager.Request(Uri.parse(url))
            .setTitle(context.getString(R.string.system_download_title, model))
            .setDescription(context.getString(R.string.system_download_description))
            // A la vista mientras baja, y un aviso al terminar: la app puede
            // estar cerrada, y es la única forma de saber que ya está.
            .setNotificationVisibility(
                DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED,
            )
            .setDestinationInExternalFilesDir(
                context,
                null,
                destination.path.removePrefix(root.path + File.separator),
            )
        val headers = call.argument<Map<String, String>>("headers").orEmpty()
        headers.forEach { (name, value) -> request.addRequestHeader(name, value) }
        if (headers.keys.none { it.equals("User-Agent", ignoreCase = true) }) {
            request.addRequestHeader("User-Agent", USER_AGENT)
        }
        result.success(manager.enqueue(request))
    }

    private fun query(id: Long): Map<String, Any?> =
        manager.query(DownloadManager.Query().setFilterById(id))?.use { cursor ->
            if (!cursor.moveToFirst()) return@use null
            val status = cursor.int(DownloadManager.COLUMN_STATUS)
            val reason = cursor.int(DownloadManager.COLUMN_REASON)
            val state = mutableMapOf<String, Any?>(
                "status" to statusName(status),
                "downloaded" to cursor.long(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR),
                "total" to cursor.long(DownloadManager.COLUMN_TOTAL_SIZE_BYTES),
            )
            if (status == DownloadManager.STATUS_FAILED) {
                // Con un error de HTTP, el motivo es el código que contestó el
                // servidor; si no, una de las constantes `ERROR_*`.
                if (reason in 400..599) {
                    state["httpStatus"] = reason
                } else {
                    state["error"] = when (reason) {
                        DownloadManager.ERROR_INSUFFICIENT_SPACE -> "insufficient_space"
                        DownloadManager.ERROR_CANNOT_RESUME -> "cannot_resume"
                        else -> "other_$reason"
                    }
                }
            }
            state
        } ?: mapOf("status" to "unknown")

    private fun statusName(status: Int): String = when (status) {
        DownloadManager.STATUS_PENDING -> "pending"
        DownloadManager.STATUS_RUNNING -> "running"
        DownloadManager.STATUS_PAUSED -> "paused"
        DownloadManager.STATUS_SUCCESSFUL -> "successful"
        DownloadManager.STATUS_FAILED -> "failed"
        else -> "unknown"
    }

    private fun MethodCall.idArgument(): Long =
        (argument<Number>("id") ?: throw IllegalArgumentException("Falta id.")).toLong()

    private fun Cursor.int(column: String) = getInt(getColumnIndexOrThrow(column))

    private fun Cursor.long(column: String) = getLong(getColumnIndexOrThrow(column))

    companion object {
        const val CHANNEL = "app.sinapsis/system_downloads"
        private const val TAG = "SystemDownloads"
        private const val USER_AGENT = "Sinapsis/0.1 (+lector de contenido personal)"

        // Los mismos nombres que `LongWorkDetail` del lado Dart.
        private const val LABEL_RELATIONS_MODEL = "relations_model"
        private const val LABEL_TRANSCRIPTION_MODEL = "transcription_model"
    }
}
