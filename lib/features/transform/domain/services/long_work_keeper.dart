import 'dart:async';

import 'package:flutter/foundation.dart';

/// Lo que mantiene viva la app mientras hay trabajo largo en curso (F21,
/// decisión C): en Android, un servicio en primer plano con su notificación
/// —sin él, el sistema congela o mata la app a los pocos minutos de salir de
/// ella, a mitad de una transcripción de horas—. En el resto de las
/// plataformas no hace falta nada.
///
/// Es el de UN dueño (`LongWorkCoordinator.keeperFor`): el procesamiento y la
/// IA que organiza sola piden y sueltan cada uno el suyo, sin pisarse.
abstract interface class LongWorkKeeper {
  /// Hay trabajo largo en curso: [done] de [total] —páginas, tramos,
  /// elementos—, o los dos en cero si todavía no se sabe cuánto hay. Se puede
  /// llamar seguido: solo cuenta lo que cambia.
  void working({required int done, required int total});

  /// Ya no hay trabajo largo en curso.
  void idle();
}

/// Donde no hace falta mantener nada vivo: la web, el escritorio, las
/// pruebas.
class NoLongWorkKeeper implements LongWorkKeeper {
  const NoLongWorkKeeper();

  @override
  void working({required int done, required int total}) {}

  @override
  void idle() {}
}

/// Quién pide mantener viva la app (F27): el servicio en primer plano es uno
/// solo, con una sola notificación, y lo comparten.
///
/// El orden es la prioridad de la notificación: si los dos trabajan, se ve
/// el avance del procesamiento —lo que la persona acaba de pedir, con su
/// porcentaje—, y el servicio sigue mientras alguno trabaje.
enum LongWorkOwner {
  /// La cola de procesamiento: transcribir, reconocer páginas (F21).
  processing,

  /// La IA que organiza sola la biblioteca que ya existía, con el cargador
  /// (F27, decisión C).
  aiOrganize,
}

/// Lo que muestra la notificación del servicio: de quién es el trabajo que
/// se ve y cuánto va.
@immutable
class LongWorkNotice {
  const LongWorkNotice({
    required this.owner,
    required this.done,
    required this.total,
  });

  final LongWorkOwner owner;
  final int done;

  /// `0` si todavía no se sabe cuánto hay.
  final int total;

  /// El porcentaje hecho; `-1` si no se sabe.
  int get percent => total <= 0 ? -1 : (done * 100 ~/ total).clamp(0, 100);

  @override
  bool operator ==(Object other) =>
      other is LongWorkNotice &&
      other.owner == owner &&
      other.done == done &&
      other.total == total;

  @override
  int get hashCode => Object.hash(owner, done, total);

  @override
  String toString() => 'LongWorkNotice(${owner.name} $done/$total)';
}

/// Lo que el coordinador le pide a la plataforma: mostrar el servicio con
/// su notificación, o apagarlo. En Android, `LongWorkService`.
abstract interface class LongWorkPlatform {
  Future<void> show(LongWorkNotice notice);

  Future<void> stop();
}

/// El servicio en primer plano, compartido por varios dueños (F27).
///
/// Hasta F27 era de la cola de procesamiento sola: la IA que organiza la
/// biblioteca existente no lo usaba, y el sistema podía congelar la app en
/// mitad de horas de trabajo con el cargador. Ahora cada dueño pide y suelta
/// el suyo ([keeperFor]), y el coordinador junta los pedidos:
///
/// - el servicio sigue mientras **alguno** trabaje; soltar uno no apaga el
///   del otro;
/// - la notificación dice lo del dueño de más prioridad ([LongWorkOwner]);
///   cuando ese suelta, pasa a decir lo del otro;
/// - solo le habla a la plataforma cuando algo cambia —otro dueño, otro
///   porcentaje, empezar, terminar—: el avance llega página por página, y
///   una notificación que se redibuja cientos de veces por minuto gasta
///   batería sin decir nada nuevo;
/// - apagar espera [releaseDelay]: entre un trabajo largo y el siguiente hay
///   un instante sin ninguno, y apagar el servicio ahí obligaría a volver a
///   prenderlo —algo que Android no deja hacer si la app está en segundo
///   plano—.
class LongWorkCoordinator {
  LongWorkCoordinator({
    required LongWorkPlatform platform,
    this.releaseDelay = const Duration(seconds: 15),
  }) : _platform = platform;

  final LongWorkPlatform _platform;
  final Duration releaseDelay;

  /// Lo que pidió cada dueño que trabaja.
  final _working = <LongWorkOwner, ({int done, int total})>{};

  /// Lo último que se le mostró a la plataforma; `null` con el servicio
  /// apagado.
  LongWorkNotice? _shown;
  Timer? _release;

  /// El guardián de [owner]: lo que la cola de ese dueño pide y suelta.
  LongWorkKeeper keeperFor(LongWorkOwner owner) => _OwnedKeeper(this, owner);

  /// Lo que se ve ahora en la notificación, para las pruebas.
  @visibleForTesting
  LongWorkNotice? get shown => _shown;

  void _report(LongWorkOwner owner, int done, int total) {
    _working[owner] = (done: done, total: total);
    _publish();
  }

  void _drop(LongWorkOwner owner) {
    if (_working.remove(owner) == null) return;
    _publish();
  }

  void _publish() {
    if (_working.isEmpty) {
      if (_shown == null || _release != null) return;
      _release = Timer(releaseDelay, () {
        _release = null;
        _shown = null;
        unawaited(_platform.stop());
      });
      return;
    }

    _release?.cancel();
    _release = null;
    final owner = LongWorkOwner.values.firstWhere(_working.containsKey);
    final work = _working[owner]!;
    final notice = LongWorkNotice(
      owner: owner,
      done: work.done,
      total: work.total,
    );
    final previous = _shown;
    if (previous != null &&
        previous.owner == notice.owner &&
        previous.percent == notice.percent) {
      return;
    }
    _shown = notice;
    unawaited(_platform.show(notice));
  }
}

class _OwnedKeeper implements LongWorkKeeper {
  _OwnedKeeper(this._coordinator, this._owner);

  final LongWorkCoordinator _coordinator;
  final LongWorkOwner _owner;

  @override
  void working({required int done, required int total}) =>
      _coordinator._report(_owner, done, total);

  @override
  void idle() => _coordinator._drop(_owner);
}

/// Donde no hay servicio que prender: la web, el escritorio.
class NoLongWorkPlatform implements LongWorkPlatform {
  const NoLongWorkPlatform();

  @override
  Future<void> show(LongWorkNotice notice) async {}

  @override
  Future<void> stop() async {}
}
