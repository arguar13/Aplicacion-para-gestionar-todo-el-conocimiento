package app.sinapsis

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Comprime un WAV a M4A (AAC-LC) con el codificador del sistema (F47, pasos
 * 5 y 6): el audio que la app genera en el teléfono —un podcast, un documento
 * para escuchar sin conexión— ocupa la sexta parte.
 *
 * Lee el WAV del disco **de a pedazos** y escribe el M4A con [MediaMuxer]: lo
 * que ocupa en memoria es un pedazo, no el audio. `audio_decoder`, que la app
 * ya trae, decodifica el archivo entero a una lista en memoria antes de
 * comprimirlo, y con una hora de audio un `OutOfMemoryError` —que no es una
 * `Exception`— tumbaría el proceso entero, con la cola de procesamiento.
 *
 * Solo PCM de 16 bits, que es lo que arma la app (`speech_wav.dart`).
 */
object WavToM4a {
    private const val TIMEOUT_US = 10_000L
    private const val CHUNK_BYTES = 16 * 1024

    private class Wav(val sampleRate: Int, val channels: Int, val dataOffset: Long, val dataLength: Long)

    fun encode(inputPath: String, outputPath: String, bitRate: Int) {
        val output = File(outputPath)
        output.delete()
        RandomAccessFile(inputPath, "r").use { input ->
            val wav = header(input)
            try {
                encode(input, wav, outputPath, bitRate)
            } catch (e: Exception) {
                output.delete()
                throw e
            }
        }
    }

    private fun encode(input: RandomAccessFile, wav: Wav, outputPath: String, bitRate: Int) {
        val format = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, wav.sampleRate, wav.channels)
        format.setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
        format.setInteger(MediaFormat.KEY_BIT_RATE, bitRate)
        format.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, CHUNK_BYTES)
        val codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
        val muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var muxing = false
        try {
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            codec.start()
            val frameBytes = 2 * wav.channels
            val chunk = ByteArray(CHUNK_BYTES)
            var remaining = wav.dataLength
            var framesQueued = 0L
            var track = -1
            var inputDone = false
            var outputDone = false
            val info = MediaCodec.BufferInfo()
            input.seek(wav.dataOffset)
            while (!outputDone) {
                if (!inputDone) {
                    val index = codec.dequeueInputBuffer(TIMEOUT_US)
                    if (index >= 0) {
                        val buffer = codec.getInputBuffer(index)!!
                        buffer.clear()
                        var size = minOf(buffer.remaining().toLong(), remaining, CHUNK_BYTES.toLong()).toInt()
                        size -= size % frameBytes
                        val time = framesQueued * 1_000_000L / wav.sampleRate
                        if (size <= 0) {
                            codec.queueInputBuffer(index, 0, 0, time, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            input.readFully(chunk, 0, size)
                            buffer.put(chunk, 0, size)
                            codec.queueInputBuffer(index, 0, size, time, 0)
                            remaining -= size
                            framesQueued += size / frameBytes
                        }
                    }
                }
                var index = codec.dequeueOutputBuffer(info, TIMEOUT_US)
                while (index != MediaCodec.INFO_TRY_AGAIN_LATER) {
                    if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                        track = muxer.addTrack(codec.outputFormat)
                        muxer.start()
                        muxing = true
                    } else if (index >= 0) {
                        val buffer = codec.getOutputBuffer(index)!!
                        // La configuración del códec ya va en el formato de la
                        // pista: escrita como muestra, sonaría un chasquido.
                        if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) info.size = 0
                        if (info.size > 0 && muxing) {
                            buffer.position(info.offset)
                            buffer.limit(info.offset + info.size)
                            muxer.writeSampleData(track, buffer, info)
                        }
                        codec.releaseOutputBuffer(index, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                            outputDone = true
                            break
                        }
                    }
                    index = codec.dequeueOutputBuffer(info, 0)
                }
            }
        } finally {
            try {
                codec.stop()
            } catch (_: IllegalStateException) {
            }
            codec.release()
            try {
                if (muxing) muxer.stop()
            } finally {
                muxer.release()
            }
        }
    }

    /** El formato del WAV: recorre sus partes sin suponer que mide 44 bytes. */
    private fun header(input: RandomAccessFile): Wav {
        val length = input.length()
        val head = ByteArray(12)
        input.seek(0)
        input.readFully(head)
        if (String(head, 0, 4, Charsets.US_ASCII) != "RIFF" || String(head, 8, 4, Charsets.US_ASCII) != "WAVE") {
            throw IllegalArgumentException("No es un WAV.")
        }
        var rate = 0
        var channels = 0
        var bits = 0
        var position = 12L
        val chunk = ByteArray(8)
        while (position + 8 <= length) {
            input.seek(position)
            input.readFully(chunk)
            val id = String(chunk, 0, 4, Charsets.US_ASCII)
            val size = ByteBuffer.wrap(chunk, 4, 4).order(ByteOrder.LITTLE_ENDIAN).int.toLong() and 0xFFFFFFFFL
            val body = position + 8
            if (id == "fmt ") {
                val fmt = ByteArray(16)
                input.readFully(fmt)
                val data = ByteBuffer.wrap(fmt).order(ByteOrder.LITTLE_ENDIAN)
                val audioFormat = data.getShort(0).toInt() and 0xFFFF
                channels = data.getShort(2).toInt() and 0xFFFF
                rate = data.getInt(4)
                bits = data.getShort(14).toInt() and 0xFFFF
                if (audioFormat != 1 || bits != 16) {
                    throw IllegalArgumentException("Solo PCM de 16 bits (formato $audioFormat, $bits bits).")
                }
            } else if (id == "data") {
                if (rate <= 0 || channels <= 0) throw IllegalArgumentException("El WAV no dice su formato.")
                return Wav(rate, channels, body, minOf(size, length - body))
            }
            position = body + size + (size and 1L)
        }
        throw IllegalArgumentException("El WAV no tiene muestras.")
    }
}
