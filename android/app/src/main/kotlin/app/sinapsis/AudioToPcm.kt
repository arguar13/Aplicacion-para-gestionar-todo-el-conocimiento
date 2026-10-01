package app.sinapsis

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.io.File
import java.io.FileOutputStream

/**
 * Decodifica cualquier audio —o la pista de audio de un video— a PCM crudo,
 * tal como lo entrega el decodificador del sistema, con el formato REAL de
 * cada tramo (F22).
 *
 * Reemplaza en Android a `audio_decoder` para transcribir, que tomaba la
 * frecuencia y los canales de lo que DECLARA el archivo y no de lo que
 * ENTREGA el decodificador: un AAC eficiente (HE-AAC, el de muchos audios
 * de YouTube y de apps de mensajes) declara 22.050 Hz y se decodifica a
 * 44.100, y el WAV salía con el doble de duración —medido en el teléfono
 * del usuario: 598,9 s para un audio de 299,4 s—. A Whisper le llegaba el
 * audio estirado, una octava más grave, y transcribía cualquier cosa.
 *
 * Acá manda el formato de cada bloque que entrega el decodificador
 * (`getOutputFormat(índice)`). No se hace ninguna cuenta muestra por
 * muestra: en una app recién instalada Android ejecuta este código
 * interpretado, y eso tardaba 113 s por cada 5 minutos de AAC. Los bytes se
 * vuelcan tal cual, y la mezcla a mono y el paso a 16 kHz los hace Dart,
 * compilado a código nativo (`pcm_resampler.dart`).
 */
object AudioToPcm {
    /** Un tramo del PCM crudo con un mismo formato. */
    data class Segment(
        val offset: Long,
        var length: Long,
        val sampleRate: Int,
        val channels: Int,
        val encoding: Int,
    ) {
        fun toMap(): Map<String, Any> = mapOf(
            "offset" to offset,
            "length" to length,
            "sampleRate" to sampleRate,
            "channels" to channels,
            "encoding" to when (encoding) {
                AudioFormat.ENCODING_PCM_FLOAT -> "float32"
                AudioFormat.ENCODING_PCM_8BIT -> "uint8"
                AudioFormat.ENCODING_PCM_32BIT -> "int32"
                else -> "int16"
            },
        )
    }

    private const val TIMEOUT_US = 2_000L

    fun decode(inputPath: String, outputPath: String): List<Segment> {
        val extractor = MediaExtractor()
        extractor.setDataSource(inputPath)
        try {
            val track = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            } ?: throw IllegalArgumentException("El archivo no tiene una pista de audio.")
            extractor.selectTrack(track)
            val format = extractor.getTrackFormat(track)
            val codec = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
            try {
                codec.configure(format, null, null, 0)
                codec.start()
                return drain(extractor, codec, File(outputPath))
            } finally {
                try {
                    codec.stop()
                } catch (_: IllegalStateException) {
                }
                codec.release()
            }
        } finally {
            extractor.release()
        }
    }

    private fun drain(extractor: MediaExtractor, codec: MediaCodec, output: File): List<Segment> {
        output.delete()
        val segments = mutableListOf<Segment>()
        val started = System.nanoTime()
        var frames = 0
        val info = MediaCodec.BufferInfo()
        var inputDone = false
        var outputDone = false
        var written = 0L
        var current: MediaFormat? = null
        try {
            FileOutputStream(output).channel.use { channel ->
                // Sin esperas de más: se carga TODA la entrada que el
                // decodificador acepte en este momento y se vacía TODA la
                // salida que ya tenga lista.
                while (!outputDone) {
                    while (!inputDone) {
                        val index = codec.dequeueInputBuffer(0)
                        if (index < 0) break
                        val buffer = codec.getInputBuffer(index)!!
                        val size = extractor.readSampleData(buffer, 0)
                        if (size < 0) {
                            codec.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            codec.queueInputBuffer(index, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                    var index = codec.dequeueOutputBuffer(info, TIMEOUT_US)
                    while (index >= 0 || index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                        if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                            // El decodificador avisa el formato que de verdad
                            // va a entregar: se lee acá, una vez, y no en cada
                            // bloque —leerlo cruza al proceso de medios del
                            // sistema, y en cada bloque sumaba decenas de
                            // segundos por cada 5 minutos de audio—.
                            current = codec.outputFormat
                            index = codec.dequeueOutputBuffer(info, 0)
                            continue
                        }
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
                        if (info.size > 0) {
                            // El formato de lo que entrega el decodificador:
                            // no el que declaraba el archivo. Si todavía no
                            // avisó ninguno, se le pregunta una vez.
                            val blockFormat = current ?: codec.getOutputFormat(index).also { current = it }
                            val rate = blockFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                            val channels = blockFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                            val encoding = if (blockFormat.containsKey(MediaFormat.KEY_PCM_ENCODING)) {
                                blockFormat.getInteger(MediaFormat.KEY_PCM_ENCODING)
                            } else {
                                AudioFormat.ENCODING_PCM_16BIT
                            }
                            val last = segments.lastOrNull()
                            if (last == null || last.sampleRate != rate || last.channels != channels ||
                                last.encoding != encoding
                            ) {
                                segments += Segment(written, 0, rate, channels, encoding)
                            }
                            val buffer = codec.getOutputBuffer(index)!!
                            buffer.position(info.offset)
                            buffer.limit(info.offset + info.size)
                            while (buffer.hasRemaining()) channel.write(buffer)
                            written += info.size
                            frames++
                            segments.last().length += info.size
                        }
                        codec.releaseOutputBuffer(index, false)
                        if (outputDone) break
                        index = codec.dequeueOutputBuffer(info, 0)
                    }
                }
            }
        } catch (e: Exception) {
            output.delete()
            throw e
        }
        // Una línea por audio, para diagnosticar desde el registro del
        // teléfono: cuánto tardó y cuántos bloques entregó el decodificador.
        android.util.Log.i(
            "AudioToPcm",
            "decodificado: ${(System.nanoTime() - started) / 1_000_000} ms, $frames bloques, $written bytes",
        )
        return segments
    }
}
