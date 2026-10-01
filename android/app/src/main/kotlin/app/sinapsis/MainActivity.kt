package app.sinapsis

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    // `receive_sharing_intent` 1.9.0 no envuelve en try/catch sus propias
    // llamadas a `ContentResolver` (`query`, `getType`, `openInputStream`)
    // en `FileDirectory.getDataColumn`, y las dispara de forma síncrona
    // desde `onNewIntent`, fuera de cualquier `MethodChannel.Result` que
    // pudiera convertir el fallo en una excepción Dart atrapable. Un
    // `content://` sin permiso de lectura válido —encontrado simulando un
    // intent de compartir a mano, sin pasar por la hoja de compartir real
    // del sistema, que sí otorga el permiso correctamente— revienta con un
    // `SecurityException` que mata la app entera antes de que el bridge de
    // Flutter llegue a enterarse: ningún `FlutterError.onError`,
    // `PlatformDispatcher.onError` ni `runZonedGuarded` del lado Dart puede
    // interceptar algo que nunca cruzó al lado Dart.
    //
    // Degradar antes que fallar (principio 4) también vale para lo que pasa
    // en Kotlin: un intent de compartir que no se puede leer no es motivo
    // para perder el resto de la sesión. Envolver acá, en la única
    // actividad que este proyecto controla, es la forma de sostener ese
    // principio sin parchear un paquete de terceros que se sobrescribiría
    // en el próximo `flutter pub get`.
    override fun onNewIntent(intent: Intent) {
        try {
            super.onNewIntent(intent)
        } catch (e: SecurityException) {
            Log.w(TAG, "Intent de compartir descartado: sin permiso para leer el URI", e)
        } catch (e: IllegalArgumentException) {
            Log.w(TAG, "Intent de compartir descartado: URI inválido o ya no existe", e)
        }
    }

    // El canal del trabajo largo (F21): la cola de Dart avisa cuándo hay
    // trabajo largo en curso y cuánto va; ver `LongWorkService`.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LONG_WORK_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "working" -> {
                        askForNotificationsOnce()
                        LongWorkService.working(
                            this,
                            call.argument<Int>("done") ?: 0,
                            call.argument<Int>("total") ?: 0,
                        )
                        result.success(null)
                    }
                    "idle" -> {
                        LongWorkService.idle(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        // Decodificar un audio para transcribirlo (F22): en un hilo aparte
        // —un audio de horas tarda—, con el resultado de vuelta en el
        // principal, que es donde Flutter lo espera. Ver `AudioToPcm`.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "toRawPcm") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val input = call.argument<String>("input")
                val output = call.argument<String>("output")
                if (input == null || output == null) {
                    result.error("arguments", "Faltan input y output.", null)
                    return@setMethodCallHandler
                }
                audioWorker.execute {
                    try {
                        val segments = AudioToPcm.decode(input, output).map { it.toMap() }
                        mainHandler.post { result.success(segments) }
                    } catch (e: Exception) {
                        mainHandler.post { result.error("decode", e.message ?: e.toString(), null) }
                    }
                }
            }
    }

    private val audioWorker = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    // Android 13 en adelante pide permiso para mostrar notificaciones. Se
    // pide la primera vez que hace falta —cuando arranca un trabajo largo—,
    // no al abrir la app sin contexto. Sin permiso el trabajo sigue igual:
    // solo no se ve la notificación.
    private fun askForNotificationsOnce() {
        if (askedForNotifications || Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        askedForNotifications = true
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATIONS_REQUEST)
    }

    private companion object {
        const val TAG = "MainActivity"
        const val LONG_WORK_CHANNEL = "app.sinapsis/long_work"
        const val AUDIO_CHANNEL = "app.sinapsis/audio"
        const val NOTIFICATIONS_REQUEST = 21
        var askedForNotifications = false
    }
}
