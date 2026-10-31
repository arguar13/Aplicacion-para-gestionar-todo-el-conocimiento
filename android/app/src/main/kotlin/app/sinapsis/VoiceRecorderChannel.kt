package app.sinapsis

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.RandomAccessFile
import kotlin.math.sqrt

/**
 * Graba la muestra de una voz que se clona (F47, paso 4): PCM de 16 bits,
 * mono, a 44,1 kHz —la única frecuencia que Android garantiza en todos los
 * teléfonos—, en un WAV. Ver, del lado de Dart, `MethodChannelVoiceRecorder`.
 *
 * Sin paquetes, como el dictado (F42): `AudioRecord` ya está en el teléfono,
 * escribe el PCM tal cual —lo que la app mide y lo que se sube para clonar— y
 * no hace falta un paquete de grabación para un solo formato.
 *
 * El canal `app.sinapsis/voice_recorder`:
 * - `isAvailable`: si el teléfono tiene micrófono. Sin permisos.
 * - `requestPermission`: pide el permiso del micrófono si hace falta y
 *   contesta si quedó concedido.
 * - `stop`: termina la grabación; lo grabado queda en el archivo.
 *
 * El canal de eventos `app.sinapsis/voice_recorder/events`: escucharlo, con
 * `{path, limitMs}`, arranca la grabación, y dejar de escucharlo la termina.
 * Cada evento es `{level, elapsedMs}` (el nivel de 0 a 1), unas diez veces por
 * segundo; termina cuando el WAV quedó escrito —por `stop` o por el límite—, y
 * con un error `permission`, `busy` o `audio` si no se pudo.
 */
class VoiceRecorderChannel(private val context: Context) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val main = Handler(Looper.getMainLooper())
    @Volatile private var recording: Recording? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(
                context.packageManager.hasSystemFeature(PackageManager.FEATURE_MICROPHONE),
            )
            "requestPermission" -> requestPermission(result)
            "stop" -> {
                recording?.stop()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        recording?.stop()
        if (!granted()) {
            events.error("permission", "Sin permiso para usar el micrófono.", null)
            events.endOfStream()
            return
        }
        val args = arguments as? Map<*, *>
        val path = args?.get("path") as? String
        val limitMs = (args?.get("limitMs") as? Number)?.toLong() ?: 180_000L
        if (path == null) {
            events.error("audio", "Sin archivo donde grabar.", null)
            events.endOfStream()
            return
        }
        val started = Recording(File(path), limitMs, events)
        recording = started
        started.start()
    }

    override fun onCancel(arguments: Any?) {
        recording?.stop()
    }

    private fun granted(): Boolean =
        context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED

    private fun requestPermission(result: MethodChannel.Result) {
        if (granted()) {
            result.success(true)
            return
        }
        val activity = SinapsisEngine.currentActivity()
        if (activity == null) {
            result.success(false)
            return
        }
        pendingPermission?.success(false)
        pendingPermission = result
        activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), PERMISSION_REQUEST)
    }

    /** Una grabación, en su propio hilo: `AudioRecord.read` bloquea. */
    private inner class Recording(
        private val file: File,
        private val limitMs: Long,
        private val events: EventChannel.EventSink,
    ) {
        @Volatile private var running = true

        fun stop() {
            running = false
        }

        private fun send(body: () -> Unit) = main.post {
            if (recording === this) body()
        }

        private fun finish(error: String? = null) = main.post {
            if (error != null) events.error(error, "No se pudo grabar.", null)
            events.endOfStream()
            if (recording === this) recording = null
        }

        fun start() {
            Thread({ run() }, "sinapsis-grabar-voz").start()
        }

        private fun run() {
            val minBuffer = AudioRecord.getMinBufferSize(
                SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
            )
            if (minBuffer <= 0) {
                finish("audio")
                return
            }
            val record = try {
                AudioRecord(
                    MediaRecorder.AudioSource.MIC,
                    SAMPLE_RATE,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                    minBuffer * 4,
                )
            } catch (e: SecurityException) {
                finish("permission")
                return
            } catch (e: IllegalArgumentException) {
                finish("audio")
                return
            }
            if (record.state != AudioRecord.STATE_INITIALIZED) {
                record.release()
                finish("busy")
                return
            }
            try {
                file.parentFile?.mkdirs()
                RandomAccessFile(file, "rw").use { out ->
                    out.setLength(0)
                    out.write(ByteArray(WAV_HEADER_BYTES))
                    val buffer = ShortArray(SAMPLE_RATE / 10)
                    val bytes = ByteArray(buffer.size * 2)
                    var samples = 0L
                    val limitSamples = limitMs * SAMPLE_RATE / 1000
                    record.startRecording()
                    if (record.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
                        finish("busy")
                        return
                    }
                    while (running && samples < limitSamples) {
                        val read = record.read(buffer, 0, buffer.size)
                        if (read < 0) {
                            finish("audio")
                            return
                        }
                        var sum = 0.0
                        for (i in 0 until read) {
                            val s = buffer[i].toInt()
                            bytes[i * 2] = (s and 0xFF).toByte()
                            bytes[i * 2 + 1] = ((s shr 8) and 0xFF).toByte()
                            val v = s / 32768.0
                            sum += v * v
                        }
                        out.write(bytes, 0, read * 2)
                        samples += read
                        val level = if (read > 0) sqrt(sum / read) else 0.0
                        val elapsed = samples * 1000 / SAMPLE_RATE
                        send {
                            events.success(
                                mapOf(
                                    "level" to (level * 3).coerceIn(0.0, 1.0),
                                    "elapsedMs" to elapsed,
                                ),
                            )
                        }
                    }
                    writeHeader(out, samples)
                }
                finish()
            } catch (e: java.io.IOException) {
                finish("audio")
            } finally {
                try {
                    record.stop()
                } catch (e: IllegalStateException) {
                    // Nunca empezó: no hay nada que parar.
                }
                record.release()
            }
        }
    }

    /** La cabecera RIFF de un WAV PCM de 16 bits, mono, con [samples] muestras. */
    private fun writeHeader(out: RandomAccessFile, samples: Long) {
        val dataBytes = samples * 2
        val header = java.nio.ByteBuffer.allocate(WAV_HEADER_BYTES)
            .order(java.nio.ByteOrder.LITTLE_ENDIAN)
        header.put("RIFF".toByteArray(Charsets.US_ASCII))
        header.putInt((36 + dataBytes).toInt())
        header.put("WAVE".toByteArray(Charsets.US_ASCII))
        header.put("fmt ".toByteArray(Charsets.US_ASCII))
        header.putInt(16)
        header.putShort(1) // PCM
        header.putShort(1) // mono
        header.putInt(SAMPLE_RATE)
        header.putInt(SAMPLE_RATE * 2)
        header.putShort(2)
        header.putShort(16)
        header.put("data".toByteArray(Charsets.US_ASCII))
        header.putInt(dataBytes.toInt())
        out.seek(0)
        out.write(header.array())
    }

    companion object {
        const val CHANNEL = "app.sinapsis/voice_recorder"
        const val EVENTS = "app.sinapsis/voice_recorder/events"
        const val PERMISSION_REQUEST = 24
        const val SAMPLE_RATE = 44100
        const val WAV_HEADER_BYTES = 44

        @Volatile private var pendingPermission: MethodChannel.Result? = null

        /** La respuesta del diálogo del permiso del micrófono. */
        fun onPermissionsResult(requestCode: Int, grantResults: IntArray) {
            if (requestCode != PERMISSION_REQUEST) return
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermission?.success(granted)
            pendingPermission = null
        }
    }
}
