import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';

/// Cómo se ve el lector flotante (F25).
enum ReadAloudPanel {
  /// Solo el botón redondo —si la pantalla tiene texto—: no se está leyendo
  /// nada.
  hidden,

  /// Leyendo (o en pausa), achicado al botón redondo con un anillo de
  /// avance.
  minimized,

  /// El mini reproductor abierto.
  expanded,
}

/// En qué va el lector flotante (F25).
@immutable
class ReadAloudState {
  const ReadAloudState({
    this.document,
    this.segmentIndex = 0,
    this.charInSegment = 0,
    this.playing = false,
    this.panel = ReadAloudPanel.hidden,
    this.speed = 1,
    this.voice,
    this.failed = false,
  });

  /// Lo que se está leyendo; `null` si nada.
  final ReadableDocument? document;

  /// Qué pedazo de [document] se lee ahora.
  final int segmentIndex;

  /// Por dónde va dentro de lo que se dice de ese pedazo (`spoken`), en
  /// caracteres: el comienzo de la palabra que se está diciendo.
  final int charInSegment;

  /// Si está sonando —o va a sonar enseguida—; `false` en pausa.
  final bool playing;

  final ReadAloudPanel panel;

  /// De 0,5 a 2.
  final double speed;

  /// `null`: la voz del sistema.
  final NarrationVoice? voice;

  /// El motor de voz falló; se ve en el reproductor.
  final bool failed;

  ReadableSegment? get currentSegment {
    final segments = document?.segments;
    if (segments == null || segmentIndex >= segments.length) return null;
    return segments[segmentIndex];
  }

  /// Cuánto leyó, de 0 a 1, por caracteres dichos: el anillo del botón.
  double get progress {
    final segments = document?.segments;
    if (segments == null || segments.isEmpty) return 0;
    var total = 0;
    var done = 0;
    for (var i = 0; i < segments.length; i++) {
      final length = segments[i].spoken.length;
      total += length;
      if (i < segmentIndex) done += length;
      if (i == segmentIndex) done += charInSegment.clamp(0, length);
    }
    return total == 0 ? 0 : done / total;
  }

  ReadAloudState copyWith({
    ReadableDocument? document,
    bool clearDocument = false,
    int? segmentIndex,
    int? charInSegment,
    bool? playing,
    ReadAloudPanel? panel,
    double? speed,
    NarrationVoice? voice,
    bool clearVoice = false,
    bool? failed,
  }) => ReadAloudState(
    document: clearDocument ? null : document ?? this.document,
    segmentIndex: segmentIndex ?? this.segmentIndex,
    charInSegment: charInSegment ?? this.charInSegment,
    playing: playing ?? this.playing,
    panel: panel ?? this.panel,
    speed: speed ?? this.speed,
    voice: clearVoice ? null : voice ?? this.voice,
    failed: failed ?? this.failed,
  );
}

/// El lector flotante: lee un [ReadableDocument] en voz alta, pedazo por
/// pedazo, con pausa de verdad y saltos de ±10 s de habla (F25).
///
/// Uno para toda la app: sigue leyendo aunque se cambie de pantalla, hasta
/// que se cierre.
class ReadAloudController extends Notifier<ReadAloudState> {
  @override
  ReadAloudState build() => const ReadAloudState();

  /// Abre el reproductor sobre [document] y empieza a leer desde el pedazo
  /// [fromSegment]. Si ya se estaba leyendo ese mismo documento, sigue
  /// donde iba y solo abre el reproductor.
  Future<void> open(ReadableDocument document, {int fromSegment = 0}) =>
      throw UnimplementedError();

  Future<void> play() => throw UnimplementedError();

  Future<void> pause() => throw UnimplementedError();

  Future<void> togglePlay() => state.playing ? pause() : play();

  /// Salta [delta] de habla —10 s para adelante o para atrás—, medidos con
  /// la voz y la velocidad de ahora, al comienzo de una palabra.
  Future<void> skip(Duration delta) => throw UnimplementedError();

  Future<void> setSpeed(double speed) => throw UnimplementedError();

  Future<void> setVoice(NarrationVoice? voice) => throw UnimplementedError();

  void minimize() => throw UnimplementedError();

  void expand() => throw UnimplementedError();

  /// Deja de leer y cierra el reproductor.
  Future<void> close() => throw UnimplementedError();
}

final readAloudControllerProvider =
    NotifierProvider<ReadAloudController, ReadAloudState>(
      ReadAloudController.new,
    );

/// Lo que se está leyendo en el texto `sourceKey` —`[start, end)` de ese
/// texto—, o `null` si el lector no está leyendo nada de él: lo que cada
/// pantalla pinta de amarillo (F25).
final readAloudHighlightProvider = Provider.family<(int, int)?, String>((
  ref,
  sourceKey,
) {
  final segment = ref.watch(
    readAloudControllerProvider.select(
      (s) => s.panel == ReadAloudPanel.hidden ? null : s.currentSegment,
    ),
  );
  if (segment == null || segment.sourceKey != sourceKey) return null;
  return (segment.start, segment.end);
});
