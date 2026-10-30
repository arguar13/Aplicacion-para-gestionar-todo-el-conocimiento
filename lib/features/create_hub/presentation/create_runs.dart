import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_organize_settings.dart';
import 'package:sinapsis/features/create_hub/domain/create_kind.dart';

/// Cómo va algo de «Crear» que está trabajando en esta pantalla (F45, paso
/// 7b): cuántas partes del texto leyó la IA de cuántas, si se sabe.
@immutable
class CreateProgress {
  const CreateProgress({this.read, this.total});

  /// Lo que se está haciendo, sin partes que contar todavía.
  static const started = CreateProgress();

  final int? read;
  final int? total;

  /// De 0 a 1, o `null` si no se sabe: un libro que se lee por partes sí; un
  /// pedido de una sola vuelta, no.
  double? get fraction {
    final read = this.read;
    final total = this.total;
    if (read == null || total == null || total <= 0) return null;
    return (read / total).clamp(0, 1).toDouble();
  }

  /// La parte que se está leyendo, contada desde 1, si hay más de una.
  int? get reading {
    final read = this.read;
    final total = this.total;
    if (read == null || total == null || total <= 1) return null;
    return read < total ? read + 1 : total;
  }

  @override
  bool operator ==(Object other) =>
      other is CreateProgress && other.read == read && other.total == total;

  @override
  int get hashCode => Object.hash(read, total);
}

/// Se canceló algo de «Crear»: no es un fallo, y no se dice nada.
class CreateCancelled implements Exception {
  const CreateCancelled();

  @override
  String toString() => 'Se canceló lo que se estaba creando.';
}

/// Una vuelta de algo de «Crear», para quien la hace: cuenta cómo va y sabe
/// si se canceló.
///
/// Cancelar corta **entre parte y parte**: lo que la IA está escribiendo en
/// ese momento —una llamada al modelo no se corta a mitad— termina solo, y
/// su resultado se descarta. Nada se guarda después de cancelar.
class CreateRun {
  CreateRun._(this._notifier, this.kind);

  final CreateRunsNotifier _notifier;
  final CreateKind kind;
  var _cancelled = false;

  /// Si se pidió cancelar.
  bool get cancelled => _cancelled;

  /// Empieza a trabajar —se ve en la hoja y en el ✨—: después de lo que se
  /// elige antes (el tipo de nota, que el modelo esté listo).
  void working() {
    throwIfCancelled();
    _notifier._report(this, CreateProgress.started);
  }

  /// Leyó [read] partes de [total]. Si se canceló, corta acá.
  void progress(int read, int total) {
    throwIfCancelled();
    _notifier._report(this, CreateProgress(read: read, total: total));
  }

  /// Lanza [CreateCancelled] si se pidió cancelar: el punto de corte entre
  /// una parte y la siguiente.
  void throwIfCancelled() {
    if (_cancelled) throw const CreateCancelled();
  }
}

/// Lo que está trabajando desde «Crear» en el elemento de esta pantalla, y
/// cómo va (F45, paso 7b): lo que muestran la hoja, con «Cancelar», y el
/// anillo del ✨.
///
/// Vive mientras la pantalla lo mira —el ✨ de su barra—: al cerrarla, lo que
/// trabajaba se cancela, como antes se perdía.
class CreateRunsNotifier
    extends StateNotifier<Map<CreateKind, CreateProgress>> {
  CreateRunsNotifier() : super(const {});

  final _runs = <CreateKind, CreateRun>{};

  /// Si [kind] está trabajando.
  bool isRunning(CreateKind kind) => _runs.containsKey(kind);

  /// Hace [body] como [kind]: una sola vez por clase, así que si ya está
  /// trabajando no hace nada. Devuelve si terminó sin que se cancelara.
  Future<bool> run(
    CreateKind kind,
    Future<void> Function(CreateRun run) body,
  ) async {
    if (_runs.containsKey(kind)) return false;
    final run = CreateRun._(this, kind);
    _runs[kind] = run;
    try {
      await body(run);
      return !run.cancelled;
    } on CreateCancelled {
      return false;
    } finally {
      if (identical(_runs[kind], run)) {
        _runs.remove(kind);
        if (mounted) state = {...state}..remove(kind);
      }
    }
  }

  /// Cancela [kind]: la fila vuelve a ofrecerlo enseguida, y lo que la IA
  /// estuviera escribiendo se descarta al llegar.
  void cancel(CreateKind kind) {
    final run = _runs.remove(kind);
    if (run == null) return;
    run._cancelled = true;
    state = {...state}..remove(kind);
  }

  /// Ya no está trabajando —cerró la hoja que elegía el tipo, o terminó de
  /// generar y pasa a revisar—: deja de verse como trabajando.
  void idle(CreateRun run) {
    if (!identical(_runs[run.kind], run) || !mounted) return;
    state = {...state}..remove(run.kind);
  }

  void _report(CreateRun run, CreateProgress progress) {
    if (!identical(_runs[run.kind], run) || !mounted) return;
    state = {...state, run.kind: progress};
  }

  @override
  void dispose() {
    for (final run in _runs.values) {
      run._cancelled = true;
    }
    _runs.clear();
    super.dispose();
  }
}

/// Lo que trabaja desde «Crear» en un elemento, por su id.
final createRunsProvider = StateNotifierProvider.autoDispose
    .family<CreateRunsNotifier, Map<CreateKind, CreateProgress>, String>(
      (ref, itemId) => CreateRunsNotifier(),
    );

/// Lo que la cola de la IA de fondo está haciendo con [itemId] según
/// [status]: organizarlo o buscarle las fechas; `null` si no está con él. Las
/// tarjetas que pide Repasar para muchos documentos no cuentan: no se
/// pidieron desde acá.
CreateKind? queuedCreateOf(AiOrganizeStatus status, String itemId) =>
    switch (status) {
      AiOrganizeWorking(itemId: final working, :final source)
          when working == itemId =>
        switch (source) {
          AiWorkSource.datesRequest => CreateKind.dates,
          AiWorkSource.flashcardsRequest => null,
          AiWorkSource.requested ||
          AiWorkSource.fresh ||
          AiWorkSource.changedNote ||
          AiWorkSource.existingLibrary => CreateKind.organize,
        },
      _ => null,
    };
