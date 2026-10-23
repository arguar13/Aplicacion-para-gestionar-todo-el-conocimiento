import 'package:flutter/material.dart';
import 'package:sinapsis/core/domain/entities/highlight_color.dart';
import 'package:sinapsis/core/domain/entities/highlight_style.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/viewer/domain/services/document_highlighter.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo que se puede hacer con lo que la persona seleccionó sobre un documento
/// real —el PDF, la página web archivada— (F38): lo que el visor le da a
/// quien arma el menú de la selección.
///
/// Es el punto de conexión de la barrita de selección: el visor sabe qué hay
/// seleccionado y dónde cae en el texto extraído, la barrita sabe qué botón
/// se apretó. Para resaltar, la barrita llama a [highlight] con el color y el
/// estilo; para copiar, a [text]; para extraer o hacer una tarjeta, a
/// [locate] y al texto.
abstract interface class DocumentSelection {
  /// El texto elegido, tal como lo muestra el documento.
  Future<String> text();

  /// Dónde cae lo elegido en el texto extraído, sin guardar nada.
  Future<SelectionLocation> locate();

  /// Resalta lo elegido con el [color] —`null`, el de siempre— y el [style],
  /// con una [note] si hay. Un resaltado por página, en un PDF.
  Future<HighlightOutcome> highlight({
    HighlightColor? color,
    HighlightStyle style = HighlightStyle.fill,
    String? note,
  });

  /// Quita la selección del documento.
  Future<void> clear();
}

/// Lo que se le dice a la persona cuando [outcome] no se pudo resaltar, o
/// `null` si salió bien o no hay nada que decir (no había nada seleccionado).
String? highlightIssueMessage(
  AppLocalizations l10n,
  HighlightOutcome outcome,
) => switch (outcome.issue) {
  null || HighlightIssue.nothingSelected => null,
  HighlightIssue.scanned => l10n.documentHighlightScanned,
  HighlightIssue.notLocated => l10n.documentHighlightNotLocated,
  HighlightIssue.notSaved =>
    outcome.failure?.localizedMessage(l10n) ?? l10n.documentHighlightNotSaved,
};

/// Resalta lo seleccionado en [selection] y, si no se pudo, lo dice con un
/// aviso (lo que hace el menú de siempre del visor). Quita la selección si
/// salió bien.
Future<void> highlightAndReport(
  BuildContext context,
  DocumentSelection selection, {
  HighlightColor? color,
  HighlightStyle style = HighlightStyle.fill,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final outcome = await selection.highlight(color: color, style: style);
  if (outcome.created) {
    await selection.clear();
    return;
  }
  final message = highlightIssueMessage(l10n, outcome);
  if (message != null) {
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
