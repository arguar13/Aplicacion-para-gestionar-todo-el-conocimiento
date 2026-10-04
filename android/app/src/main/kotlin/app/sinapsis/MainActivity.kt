package app.sinapsis

import android.content.Context
import android.content.Intent
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

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

    // El motor es el del proceso (F29), no uno propio: sobrevive a esta
    // actividad para que el trabajo siga con la app cerrada, y la próxima
    // actividad se engancha al mismo, con Dart ya andando. Ver
    // `SinapsisEngine`, que también instala los canales de la app.
    override fun provideFlutterEngine(context: Context): FlutterEngine =
        SinapsisEngine.obtain(this)

    // Explícito aunque sea lo que `FlutterActivity` hace con un motor que
    // no creó ella: que cerrar la actividad no destruya el motor es
    // justamente lo que hace seguir al trabajo.
    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        SinapsisEngine.attach(this)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        SinapsisEngine.detach(this)
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private companion object {
        const val TAG = "MainActivity"
    }
}
