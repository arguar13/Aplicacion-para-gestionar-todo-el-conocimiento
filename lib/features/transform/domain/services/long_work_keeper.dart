import 'dart:async';

import 'package:flutter/foundation.dart';

/// Lo que mantiene viva la app mientras hay trabajo largo en curso (F21,
/// decisión C): en Android, un servicio en primer plano con su notificación
/// —sin él, el sistema congela o mata la app a los pocos minutos de salir de
/// ella, a mitad de una transcripción de horas o de una descarga de gigas—.
/// En el resto de las plataformas no hace falta nada.
///
/// Es el de UN trabajo (`LongWorkCoordinator.keeperFor`): el procesamiento,
/// cada descarga y la IA que organiza sola piden y sueltan cada uno el suyo,
/// sin pisarse.
abstract interface class LongWorkKeeper {
  /// Hay trabajo largo en curso: [done] de [total] —páginas, tramos,
  /// elementos, milésimas de una descarga—, o los dos en cero si todavía no
  /// se sabe cuánto hay. Se puede llamar seguido: solo cuenta lo que cambia.
  ///
  /// [kind] dice qué clase de trabajo es, para que Android lo cuente en el
  /// tipo de servicio que corresponde (ver [LongWorkKind]); [detail], lo que
  /// la notificación necesita para decir qué se hace (ver [LongWorkDetail]).
  void working({
    required int done,
    required int total,
    LongWorkKind kind = LongWorkKind.dataSync,
    String? detail,
  });

  /// Ya no hay trabajo largo en curso.
  void idle();
}

/// Qué clase de trabajo es, para el tipo del servicio en primer plano.
///
/// Desde Android 15 cada tipo tiene un tope de 6 horas cada 24, contado
/// aparte, y el sistema lo hace cumplir: usar el que corresponde a cada
/// trabajo hace que una descarga larga no le gaste el tiempo a una
/// transcripción, y es lo que Google Play pide declarar.
enum LongWorkKind {
  /// Traer o mover datos: bajar un modelo, un audio, una página; también la
  /// IA ordenando la biblioteca, que lee y escribe la base. `dataSync`.
  dataSync,

  /// Procesar medios: transcribir audio, reconocer el texto de páginas
  /// escaneadas. `mediaProcessing` desde Android 15; antes ese tipo no
  /// existe y va como `dataSync`.
  mediaProcessing,
}

/// Lo que la notificación necesita saber, además del dueño, para decir qué
/// se está haciendo.
abstract final class LongWorkDetail {
  /// [LongWorkOwner.modelDownload]: qué modelo se baja.
  static const languageModel = 'language_model';
  static const relationsModel = 'relations_model';
  static const transcriptionModel = 'transcription_model';

  /// [LongWorkOwner.aiOrganize]: la biblioteca que ya existía, que solo se
  /// recorre con el cargador puesto.
  static const whileCharging = 'while_charging';

  /// [LongWorkOwner.aiOrganize]: las tarjetas que se pidieron desde Repasar
  /// (F30), con cuántos elementos van de cuántos.
  static const flashcards = 'flashcards';
}

/// Donde no hace falta mantener nada vivo: la web, el escritorio, las
/// pruebas.
class NoLongWorkKeeper implements LongWorkKeeper {
  const NoLongWorkKeeper();

  @override
  void working({
    required int done,
    required int total,
    LongWorkKind kind = LongWorkKind.dataSync,
    String? detail,
  }) {}

  @override
  void idle() {}
}

/// Quién pide mantener viva la app (F27): el servicio en primer plano es uno
/// solo, con una sola notificación, y lo comparten.
///
/// El orden es la prioridad de la notificación: si varios trabajan, se ve el
/// del primero —lo que la persona acaba de pedir, con su porcentaje—, y el
/// servicio sigue mientras alguno trabaje.
enum LongWorkOwner {
  /// La cola de procesamiento: traer páginas y videos, transcribir,
  /// reconocer páginas (F21).
  processing,

  /// La descarga de un modelo —de lenguaje, de relaciones, de
  /// transcripción—: la pidió la persona con un botón, y pesa gigas.
  modelDownload,

  /// La bajada automática del audio de un video de YouTube (F24).
  audioDownload,

  /// La IA que organiza sola (F27): lo nuevo, lo pedido, las notas y, con el
  /// cargador, la biblioteca que ya existía.
  aiOrganize,

  /// La carga de la biblioteca de ejemplo, solo en desarrollo: bajar decenas
  /// de archivos lleva minutos, y quien la pidió sigue usando el teléfono.
  /// Última en prioridad: lo que se carga pasa enseguida a la cola de
  /// procesamiento, y el avance de esa es el que más dice.
  sampleLibrary,
}

/// Lo que muestra la notificación del servicio —de quién es el trabajo que
/// se ve y cuánto va— y con qué tipos tiene que correr el servicio: los de
/// **todos** los trabajos en curso, no solo el que se ve.
@immutable
class LongWorkNotice {
  const LongWorkNotice({
    required this.owner,
    required this.done,
    required this.total,
    this.detail,
    this.kinds = const {LongWorkKind.dataSync},
  });

  final LongWorkOwner owner;
  final int done;

  /// `0` si todavía no se sabe cuánto hay.
  final int total;

  /// Ver [LongWorkDetail].
  final String? detail;

  final Set<LongWorkKind> kinds;

  /// El porcentaje hecho; `-1` si no se sabe.
  int get percent => total <= 0 ? -1 : (done * 100 ~/ total).clamp(0, 100);

  /// Si mostrar [other] en lugar de esta no cambiaría nada de lo que se ve
  /// ni el tipo del servicio.
  bool looksLike(LongWorkNotice other) =>
      other.owner == owner &&
      other.percent == percent &&
      other.detail == detail &&
      setEquals(other.kinds, kinds);

  @override
  bool operator ==(Object other) =>
      other is LongWorkNotice &&
      other.owner == owner &&
      other.done == done &&
      other.total == total &&
      other.detail == detail &&
      setEquals(other.kinds, kinds);

  @override
  int get hashCode =>
      Object.hash(owner, done, total, detail, Object.hashAllUnordered(kinds));

  @override
  String toString() =>
      'LongWorkNotice(${owner.name} $done/$total'
      '${detail == null ? '' : ' $detail'} ${kinds.map((k) => k.name)})';
}

/// Lo que el coordinador le pide a la plataforma: mostrar el servicio con
/// su notificación, o apagarlo. En Android, `LongWorkService`.
abstract interface class LongWorkPlatform {
  Future<void> show(LongWorkNotice notice);

  Future<void> stop();

  /// El sistema cortó el servicio por su cuenta: desde Android 15, al
  /// llegar al tope de horas de su tipo. Desde ahí la app ya no está
  /// protegida, y Android no deja volver a prender el servicio hasta que la
  /// persona la traiga al frente.
  Stream<void> get stoppedBySystem;
}

/// El servicio en primer plano, compartido por varios trabajos (F27).
///
/// Cada trabajo pide y suelta el suyo ([keeperFor]) —el procesamiento, cada
/// descarga, la IA—, y el coordinador junta los pedidos:
///
/// - el servicio sigue mientras **alguno** trabaje; soltar uno no apaga el
///   de otro;
/// - la notificación dice lo del de más prioridad ([LongWorkOwner]); cuando
///   ese suelta, pasa a decir lo del siguiente. Entre dos del mismo dueño,
///   lo del que empezó antes;
/// - el servicio corre con los tipos ([LongWorkKind]) de todos los que
///   trabajan;
/// - solo le habla a la plataforma cuando algo cambia —otro dueño, otro
///   porcentaje, otro tipo, empezar, terminar—: el avance llega página por
///   página, y una notificación que se redibuja cientos de veces por minuto
///   gasta batería sin decir nada nuevo;
/// - apagar espera [releaseDelay]: entre un trabajo largo y el siguiente hay
///   un instante sin ninguno, y apagar el servicio ahí obligaría a volver a
///   prenderlo —algo que Android no deja hacer si la app está en segundo
///   plano—;
/// - si el sistema corta el servicio (`LongWorkPlatform.stoppedBySystem`),
///   no se insiste —desde segundo plano no se puede—: el trabajo sigue sin
///   la garantía, y al volver la app al frente ([appResumed]) el servicio
///   vuelve con lo que siga en curso.
class LongWorkCoordinator {
  LongWorkCoordinator({
    required LongWorkPlatform platform,
    this.releaseDelay = const Duration(seconds: 15),
  }) : _platform = platform {
    _systemStops = platform.stoppedBySystem.listen((_) => _stoppedBySystem());
  }

  final LongWorkPlatform _platform;
  final Duration releaseDelay;

  late final StreamSubscription<void> _systemStops;

  /// Lo que pidió cada trabajo en curso, en el orden en que empezó.
  final _working = <_OwnedKeeper, _Work>{};

  /// Lo último que se le mostró a la plataforma; `null` con el servicio
  /// apagado.
  LongWorkNotice? _shown;
  Timer? _release;

  /// El sistema cortó el servicio y la app no volvió al frente desde
  /// entonces: no se le pide nada a la plataforma.
  var _stoppedUntilResumed = false;

  /// Ya se descartó: lo que suelten después los trabajos —que se descartan
  /// junto con él, en cualquier orden— no arma un temporizador que nadie va
  /// a cancelar.
  var _disposed = false;

  /// El guardián de un trabajo de [owner]. Uno por trabajo: dos descargas a
  /// la vez piden cada una el suyo.
  LongWorkKeeper keeperFor(LongWorkOwner owner) => _OwnedKeeper(this, owner);

  /// Si hay algún trabajo largo en curso. Lo mira la ayuda "Que siga con la
  /// app cerrada" (F29), que se ofrece al volver a la app con trabajo.
  bool get isWorking => _working.isNotEmpty;

  /// Lo que se ve ahora en la notificación, para las pruebas.
  @visibleForTesting
  LongWorkNotice? get shown => _shown;

  /// La app volvió al frente. Si el sistema había cortado el servicio,
  /// vuelve con lo que siga en curso: con la app al frente Android lo deja
  /// prender, y el tope de horas de su tipo vuelve a contar desde cero.
  void appResumed() {
    if (!_stoppedUntilResumed) return;
    _stoppedUntilResumed = false;
    _publish();
  }

  Future<void> dispose() async {
    _disposed = true;
    _release?.cancel();
    _release = null;
    await _systemStops.cancel();
  }

  void _report(_OwnedKeeper keeper, _Work work) {
    _working[keeper] = work;
    _publish();
  }

  void _drop(_OwnedKeeper keeper) {
    if (_working.remove(keeper) == null) return;
    _publish();
  }

  void _stop() {
    _shown = null;
    unawaited(_platform.stop());
  }

  void _stoppedBySystem() {
    _release?.cancel();
    _release = null;
    _shown = null;
    _stoppedUntilResumed = true;
  }

  void _publish() {
    if (_disposed || _stoppedUntilResumed) return;
    if (_working.isEmpty) {
      if (_shown == null || _release != null) return;
      if (releaseDelay == Duration.zero) {
        // Sin margen: se apaga en el acto, sin un temporizador de por medio.
        _stop();
        return;
      }
      _release = Timer(releaseDelay, () {
        _release = null;
        _stop();
      });
      return;
    }

    _release?.cancel();
    _release = null;
    // El de más prioridad; entre los del mismo dueño, el primero que empezó
    // (el mapa guarda el orden).
    final top = _working.entries.reduce(
      (best, next) => next.key.owner.index < best.key.owner.index ? next : best,
    );
    final work = top.value;
    final notice = LongWorkNotice(
      owner: top.key.owner,
      done: work.done,
      total: work.total,
      detail: work.detail,
      kinds: {for (final w in _working.values) w.kind},
    );
    final previous = _shown;
    if (previous != null && previous.looksLike(notice)) return;
    _shown = notice;
    unawaited(_platform.show(notice));
  }
}

/// Lo que pidió un trabajo la última vez.
typedef _Work = ({int done, int total, LongWorkKind kind, String? detail});

class _OwnedKeeper implements LongWorkKeeper {
  _OwnedKeeper(this._coordinator, this.owner);

  final LongWorkCoordinator _coordinator;
  final LongWorkOwner owner;

  @override
  void working({
    required int done,
    required int total,
    LongWorkKind kind = LongWorkKind.dataSync,
    String? detail,
  }) => _coordinator._report(this, (
    done: done,
    total: total,
    kind: kind,
    detail: detail,
  ));

  @override
  void idle() => _coordinator._drop(this);
}

/// Donde no hay servicio que prender: la web, el escritorio.
class NoLongWorkPlatform implements LongWorkPlatform {
  const NoLongWorkPlatform();

  @override
  Future<void> show(LongWorkNotice notice) async {}

  @override
  Future<void> stop() async {}

  @override
  Stream<void> get stoppedBySystem => const Stream.empty();
}
