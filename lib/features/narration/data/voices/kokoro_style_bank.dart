import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sinapsis/features/narration/domain/voices/mine/kokoro_blend.dart';

/// El `voices.bin` de las voces creadas en el teléfono (F47, paso 4): una
/// copia del de Kokoro con cada voz creada en su lugar —su `sid`—, que el
/// motor carga como cualquier `voices.bin`.
///
/// **Por qué una copia del mismo tamaño y no un hablante más** (comprobado en
/// `offline-tts-kokoro-model.cc` de sherpa-onnx v1.13.8):
///
/// - el formato es el más simple: números de 32 bits, uno tras otro, sin
///   cabecera; cada hablante, [kokoroStyleRows] filas de [kokoroStyleWidth]
///   (`generate_voices_bin.py` escribe `tobytes()` de cada `.pt`, de forma
///   510 × 1 × 256);
/// - el motor lee **cuántos hablantes hay de los metadatos del modelo**
///   (`n_speakers`, 54 en v1.0), no del archivo, y exige que el archivo tenga
///   exactamente `n_speakers × 510 × 256` números: si no, **termina el
///   proceso** (`SHERPA_ONNX_EXIT(-1)`), no da un error. Y un `sid` de más se
///   lee como el 0.
///
/// Así que una voz nueva no se puede agregar al final: **ocupa el lugar** de
/// una voz de Kokoro en un archivo propio, del mismo tamaño que el original.
/// Los lugares que no usa ninguna voz creada quedan con la voz original, que
/// nadie pide. Caben [kokoroSpeakerSlots] voces creadas.
///
/// Se escribe en un isolate —son 28 MB— en un archivo aparte que recién al
/// final toma el nombre: el motor nunca lee uno a medias.
class KokoroStyleBank {
  const KokoroStyleBank();

  /// Lo que pesa un hablante en el archivo, en bytes.
  static const speakerBytes = kokoroStyleRows * kokoroStyleWidth * 4;

  /// Cuántos hablantes trae un `voices.bin` de [bytes] bytes, o `null` si
  /// ese tamaño no es el de un `voices.bin` de Kokoro v1.0.
  static int? speakersIn(int bytes) =>
      bytes > 0 && bytes % speakerBytes == 0 ? bytes ~/ speakerBytes : null;

  /// Escribe en [target] una copia de [source] —el `voices.bin` de Kokoro—
  /// con cada mezcla de [blends] en su lugar. Falla con
  /// [KokoroStyleBankException] si [source] no tiene el tamaño de un
  /// `voices.bin`, si un lugar o una voz de una mezcla no existen en él.
  Future<void> write({
    required String source,
    required String target,
    required Map<int, KokoroBlend> blends,
  }) {
    final plan = {
      for (final MapEntry(:key, :value) in blends.entries)
        key: (
          [for (final p in value.timbre) (p.speakerId, p.weight)],
          [for (final p in value.prosody) (p.speakerId, p.weight)],
        ),
    };
    return Isolate.run(() => writeStyleBank(source, target, plan));
  }
}

/// Las dos mitades de una mezcla, como pares (sid, peso): lo que cruza al
/// isolate.
typedef BlendHalves = (List<(int, double)>, List<(int, double)>);

/// [KokoroStyleBank.write], en el isolate que la llama.
void writeStyleBank(
  String source,
  String target,
  Map<int, BlendHalves> blends,
) {
  final bytes = File(source).readAsBytesSync();
  final speakers = KokoroStyleBank.speakersIn(bytes.length);
  if (speakers == null) {
    throw KokoroStyleBankException(
      'el voices.bin mide ${bytes.length} bytes, que no son hablantes enteros',
    );
  }
  // Una copia alineada: `readAsBytesSync` no promete que lo esté.
  final styles = Float32List(bytes.length ~/ 4)
    ..setAll(0, Float32List.view(Uint8List.fromList(bytes).buffer));
  final original = Float32List.fromList(styles);
  const rows = kokoroStyleRows;
  const width = kokoroStyleWidth;
  const perSpeaker = rows * width;

  for (final MapEntry(key: slot, value: (timbre, prosody)) in blends.entries) {
    if (slot < 0 || slot >= speakers) {
      throw KokoroStyleBankException('el lugar $slot no está (hay $speakers)');
    }
    for (final (sid, _) in [...timbre, ...prosody]) {
      if (sid < 0 || sid >= speakers) {
        throw KokoroStyleBankException('la voz $sid no está (hay $speakers)');
      }
    }
    final base = slot * perSpeaker;
    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < width; column++) {
        final half = column < kokoroTimbreWidth ? timbre : prosody;
        var value = 0.0;
        for (final (sid, weight) in half) {
          value += original[sid * perSpeaker + row * width + column] * weight;
        }
        styles[base + row * width + column] = value;
      }
    }
  }

  File(target).parent.createSync(recursive: true);
  File('$target.escribiendo')
    ..writeAsBytesSync(styles.buffer.asUint8List(), flush: true)
    ..renameSync(target);
}

/// No se pudo armar el `voices.bin` de las voces creadas.
class KokoroStyleBankException implements Exception {
  const KokoroStyleBankException(this.detail);

  final String detail;

  @override
  String toString() => 'No se pudieron mezclar las voces: $detail.';
}
