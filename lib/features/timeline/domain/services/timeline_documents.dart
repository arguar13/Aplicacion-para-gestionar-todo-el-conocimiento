import 'package:sinapsis/core/domain/entities/note_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/services/vocabulary_normalizer.dart';
import 'package:sinapsis/features/timeline/domain/entities/timeline_event.dart';

/// Un elemento que tiene fechas en la línea de tiempo, con lo que hace falta
/// para elegirlo en la hoja de «Documento» (F40).
class TimelineDocument {
  const TimelineDocument({
    required this.itemId,
    required this.title,
    required this.sourceKind,
    required this.noteKind,
    required this.eventCount,
    required this.firstDate,
    required this.lastDate,
  });

  final String itemId;
  final String title;
  final SourceKind sourceKind;
  final NoteKind? noteKind;

  /// Cuántas fechas tiene: un elemento con dos «Fecha del hecho» son dos
  /// hechos de un mismo documento.
  final int eventCount;

  /// La fecha más temprana y la más tardía, tal como se escriben ("44 a.C.").
  final String firstDate;
  final String lastDate;

  /// De cuándo a cuándo van sus fechas: una sola si todas son la misma.
  String get range =>
      firstDate == lastDate ? firstDate : '$firstDate – $lastDate';
}

/// Agrupa [events] por elemento —con el título del **documento**, no el del
/// hecho: un hecho fechado se llama como lo que pasó—, ordenados por título
/// (sin distinguir mayúsculas ni acentos, como el vocabulario): quien busca un
/// documento lo busca por su nombre.
///
/// Un solo recorrido sobre los hechos, no uno por documento: con diez mil
/// hechos la hoja se arma de una vez.
List<TimelineDocument> groupTimelineDocuments(Iterable<TimelineEvent> events) {
  final byItem = <String, _Group>{};
  for (final event in events) {
    final group = byItem[event.itemId];
    if (group == null) {
      byItem[event.itemId] = _Group(event);
    } else {
      group.add(event);
    }
  }

  final sortKey = <String, String>{
    for (final entry in byItem.entries)
      entry.key: normalizeVocabularyLabel(entry.value.first.documentTitle),
  };
  return [
    for (final entry in byItem.entries)
      TimelineDocument(
        itemId: entry.key,
        title: entry.value.first.documentTitle,
        sourceKind: entry.value.first.sourceKind,
        noteKind: entry.value.first.noteKind,
        eventCount: entry.value.count,
        firstDate: entry.value.earliest.date.label,
        lastDate: (entry.value.latest.end ?? entry.value.latest.date).label,
      ),
  ]..sort((a, b) {
    final byTitle = sortKey[a.itemId]!.compareTo(sortKey[b.itemId]!);
    return byTitle != 0 ? byTitle : a.itemId.compareTo(b.itemId);
  });
}

/// Lo que se va sabiendo de un elemento mientras se recorren sus hechos.
class _Group {
  _Group(TimelineEvent event)
    : first = event,
      earliest = event,
      latest = event,
      count = 1;

  final TimelineEvent first;
  TimelineEvent earliest;
  TimelineEvent latest;
  int count;

  void add(TimelineEvent event) {
    count++;
    if (event.from < earliest.from) earliest = event;
    if (event.to > latest.to) latest = event;
  }
}
