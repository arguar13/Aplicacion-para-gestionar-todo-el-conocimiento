import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sinapsis/core/domain/entities/inbox_status.dart';

part 'inbox_standing.freezed.dart';

/// Dónde está una fuente respecto de la Bandeja, y desde cuándo (F28): lo que
/// dice el chip «Triado el 3 oct» del detalle.
///
/// [since] sale de la versión por campo de `state` (`field_version`, F11): la
/// última vez que alguien cambió el estado de trabajo de la fuente. No hizo
/// falta una columna nueva —cada cambio de estado ya pasaba por
/// `KnowledgeEntryWriter`, que lo registra—. Es `null` en lo que no cambió de
/// estado desde antes de F11, cuando eso no se anotaba.
///
/// [hasText] dice si el elemento ya tiene texto (F30, decisión 68): a la
/// Bandeja solo entra lo que lo tiene, así que «Volver a la Bandeja» no se
/// ofrece en lo que no.
@freezed
sealed class InboxStanding with _$InboxStanding {
  const factory InboxStanding({
    required InboxStatus status,
    DateTime? since,
    @Default(true) bool hasText,
  }) = _InboxStanding;
}
