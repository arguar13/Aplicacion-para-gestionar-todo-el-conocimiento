package app.sinapsis

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.FlutterShellArgs
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference
import java.util.concurrent.Executors

/**
 * El motor de Flutter de la app: uno por proceso, que **sobrevive a la
 * actividad** (F29).
 *
 * Por defecto `FlutterActivity` crea su propio motor y lo destruye con ella:
 * al cerrar la app desde "recientes" se iba todo Dart —la cola de
 * procesamiento, la transcripción a medias, la IA que organiza— aunque el
 * servicio en primer plano siguiera manteniendo vivo el proceso. Ahora el
 * motor vive en el proceso, guardado en [FlutterEngineCache]: la actividad lo
 * usa sin ser su dueña, y al volver a abrir la app la actividad nueva se
 * engancha a ese mismo motor —Dart no vuelve a arrancar, no se duplica
 * ninguna cola ni estado—. Si el proceso murió, no hay motor guardado y todo
 * arranca como siempre, retomando lo pendiente desde la base.
 *
 * Por eso los canales de la app se instalan acá, con el contexto de la
 * aplicación, y no en la actividad: el trabajo largo tiene que poder avisar
 * que terminó, y la transcripción decodificar audio, con la actividad ya
 * destruida. Lo único que necesita una actividad —pedir permiso para las
 * notificaciones, abrir ajustes del sistema— la usa si hay una ([attach]).
 */
object SinapsisEngine {
    private const val ENGINE_ID = "sinapsis"
    private const val LONG_WORK_CHANNEL = "app.sinapsis/long_work"
    private const val AUDIO_CHANNEL = "app.sinapsis/audio"
    private const val DEVICE_BOOT_CHANNEL = "app.sinapsis/device_boot"
    private const val NOTIFICATIONS_REQUEST = 21

    private val audioWorker = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    /** La actividad que muestra la app ahora, si hay una. */
    private var activity: WeakReference<Activity>? = null

    private var askedForNotifications = false

    /**
     * El motor del proceso; lo crea la primera actividad, con sus argumentos
     * de arranque (los que pasa `flutter run`, por ejemplo).
     *
     * Dart no se arranca acá: lo arranca la actividad la primera vez que se
     * engancha, igual que con un motor propio —con su ruta inicial y su
     * punto de entrada—, y las siguientes lo encuentran andando.
     */
    fun obtain(activity: Activity): FlutterEngine {
        FlutterEngineCache.getInstance().get(ENGINE_ID)?.let { return it }
        val context = activity.applicationContext
        val engine = FlutterEngine(
            context,
            FlutterShellArgs.fromIntent(activity.intent).toArray(),
        )
        installChannels(context, engine)
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
        return engine
    }

    /** [activity] muestra la app. */
    fun attach(activity: Activity) {
        this.activity = WeakReference(activity)
    }

    /** [activity] ya no la muestra; si otra la reemplazó, no se toca. */
    fun detach(activity: Activity) {
        if (this.activity?.get() === activity) this.activity = null
    }

    /** La actividad que muestra la app, si hay una y no se está cerrando. */
    fun currentActivity(): Activity? = activity?.get()?.takeUnless { it.isFinishing }

    private fun installChannels(context: Context, engine: FlutterEngine) {
        val messenger = engine.dartExecutor.binaryMessenger

        // El canal del trabajo largo (F21): Dart avisa cuándo hay trabajo
        // largo en curso, de qué clase y cuánto va; Android le avisa si cortó
        // el servicio por su cuenta. Ver `LongWorkService`.
        val longWork = MethodChannel(messenger, LONG_WORK_CHANNEL)
        longWork.setMethodCallHandler { call, result ->
            when (call.method) {
                "working" -> {
                    askForNotificationsOnce()
                    LongWorkService.working(
                        context,
                        call.argument<String>("kind"),
                        call.argument<String>("detail"),
                        call.argument<Int>("done") ?: 0,
                        call.argument<Int>("total") ?: 0,
                        call.argument<List<String>>("types"),
                    )
                    result.success(null)
                }
                "idle" -> {
                    LongWorkService.idle(context)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        // `onTimeout` llega en el hilo principal, el mismo donde el canal
        // espera que se lo use. Mientras haya motor hay Dart a quien avisarle,
        // haya o no actividad.
        LongWorkService.onStoppedBySystem = { type ->
            longWork.invokeMethod("timedOut", mapOf("type" to type))
        }

        // Decodificar un audio para transcribirlo (F22): en un hilo aparte
        // —un audio de horas tarda—, con el resultado de vuelta en el
        // principal, que es donde Flutter lo espera. Ver `AudioToPcm`.
        MethodChannel(messenger, AUDIO_CHANNEL).setMethodCallHandler { call, result ->
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

        // Las descargas de los modelos con el gestor del sistema (F29).
        MethodChannel(messenger, SystemDownloadsChannel.CHANNEL)
            .setMethodCallHandler(SystemDownloadsChannel(context))

        // Los ajustes que deciden si el sistema deja seguir el trabajo con
        // la app cerrada (F29): "Inicio automático" y el ahorro de batería.
        MethodChannel(messenger, BackgroundSettingsChannel.CHANNEL)
            .setMethodCallHandler(BackgroundSettingsChannel(context))

        // El encendido del teléfono, para que la bóveda pida la clave una
        // vez por encendido: el contador de arranques del sistema, que sube
        // en uno cada vez que el teléfono arranca. Sin permisos. Antes de
        // Android 7 no existe: `null`, y la bóveda la pide siempre.
        MethodChannel(messenger, DEVICE_BOOT_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method != "bootCount") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
                result.success(null)
                return@setMethodCallHandler
            }
            result.success(
                Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT),
            )
        }
    }

    // Android 13 en adelante pide permiso para mostrar notificaciones. Se
    // pide la primera vez que hace falta —cuando arranca un trabajo largo—,
    // no al abrir la app sin contexto, y solo con la app a la vista: sin
    // actividad no hay dónde preguntarlo. Sin permiso el trabajo sigue igual:
    // solo no se ve la notificación.
    private fun askForNotificationsOnce() {
        if (askedForNotifications || Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val activity = currentActivity() ?: return
        askedForNotifications = true
        if (activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        activity.requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATIONS_REQUEST,
        )
    }
}
