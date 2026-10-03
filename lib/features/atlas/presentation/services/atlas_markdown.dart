import 'package:sinapsis/features/atlas/domain/entities/atlas_node.dart';
import 'package:sinapsis/features/atlas/domain/entities/atlas_snapshot.dart';
import 'package:sinapsis/features/atlas/presentation/widgets/atlas_labels.dart';
import 'package:sinapsis/features/atlas/presentation/widgets/coverage_meter.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El Atlas como un documento Markdown, para tener el índice FUERA de la app
/// (F13): la jerarquía de temas con sus conteos, el estado de cobertura, los
/// años que cubre cada rama, sus notas mapa y los vacíos detectados.
///
/// Es una lista anidada —una sangría de dos espacios por nivel—, que cualquier
/// lector de Markdown entiende. Las notas mapa van como `[[enlaces]]`, el
/// mismo formato con que la app enlaza notas y que Obsidian y compañía
/// reconocen.
///
/// Sale en el idioma de la app [l10n], con [now] como fecha de generación. Es
/// una foto: no se actualiza sola —para eso está la pantalla—.
///
/// [title] es cómo se llama lo que se mira —«Temas», «Etiquetas»— cuando no
/// es el nombre de la categoría tal cual está en la base (F28).
String atlasToMarkdown(
  AtlasSnapshot snapshot,
  AppLocalizations l10n, {
  required DateTime now,
  String? title,
}) {
  final subject = title ?? snapshot.definitionName;
  final out = StringBuffer()
    ..writeln('# ${l10n.atlasTitle} — ${_escape(subject)}')
    ..writeln()
    ..writeln(
      '_${l10n.atlasExportGenerated(_date(now), snapshot.nodes.length)}_',
    );

  if (snapshot.gaps.isNotEmpty) {
    out
      ..writeln()
      ..writeln('## ${l10n.atlasGapsTitle(snapshot.gaps.length)}')
      ..writeln();
    for (final gap in snapshot.gaps) {
      final node = snapshot.nodeOf(gap.valueId);
      if (node == null) continue;
      final message = atlasGapMessage(l10n, gap, node, now);
      out.writeln('- **${_escape(node.label)}** — $message');
    }
  }

  if (snapshot.nodes.isNotEmpty) {
    out
      ..writeln()
      ..writeln('## ${l10n.atlasExportTopics}')
      ..writeln();
    for (final node in snapshot.nodes) {
      out.writeln(_nodeLine(l10n, node));
    }
  }
  return out.toString();
}

/// Una rama: su nombre, su cobertura, cuánto tiene, qué años cubre y sus
/// notas mapa, sangrada según su nivel.
String _nodeLine(AppLocalizations l10n, AtlasNode node) {
  final axis = atlasAxisText(l10n, node);
  final mapNotes = [
    for (final note in node.mapNotes) '[[${_linkTitle(note.title)}]]',
  ];
  final parts = [
    node.coverage.label(l10n),
    if (node.sourceCount > 0) l10n.atlasSourceCount(node.sourceCount),
    if (node.noteCount > 0) l10n.atlasNoteCount(node.noteCount),
    if (axis != null) axis,
    if (mapNotes.isNotEmpty) l10n.atlasExportMapNotes(mapNotes.join(', ')),
  ];
  final indent = '  ' * node.depth;
  return '$indent- **${_escape(node.label)}** — ${parts.join(' · ')}';
}

/// La fecha como `2026-09-21`: la que se entiende igual en cualquier idioma.
String _date(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// Lo que en Markdown daría formato, sin darlo: un tema llamado «C*» o «[1]»
/// no puede romper la lista.
String _escape(String text) =>
    text.replaceAllMapped(RegExp(r'[\\`*_{}\[\]<>#|~]'), (m) => '\\${m[0]}');

/// El título de una nota como destino de un `[[enlace]]`: sin los caracteres
/// que un enlace no admite.
String _linkTitle(String title) => title
    .replaceAll(RegExp(r'[\[\]|#^]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
