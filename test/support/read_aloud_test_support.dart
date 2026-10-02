import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';

/// Un lector flotante sin motor de voz (F25), para probar lo que cada
/// pantalla hace con él: qué ofrece, qué pinta de amarillo, qué página da
/// vuelta. Se pone con
/// `readAloudControllerProvider.overrideWith(FakeReadAloudController.new)`.
class FakeReadAloudController extends ReadAloudController {
  @override
  ReadAloudState build() => const ReadAloudState();

  /// Deja al lector leyendo el pedazo [segment] de [document], con el
  /// reproductor abierto: lo que pasa después de tocar el botón flotante.
  void readAt(ReadableDocument document, int segment) => state = ReadAloudState(
    document: document,
    segmentIndex: segment,
    playing: true,
    panel: ReadAloudPanel.expanded,
  );
}

/// Lo que se ve en amarillo —lo que está leyendo el lector— en los textos
/// de [within] (toda la pantalla si es `null`), uno por texto, en orden.
List<String> readAloudHighlights(WidgetTester tester, {Finder? within}) {
  Finder all(Type type) => within == null
      ? find.byType(type)
      : find.descendant(of: within, matching: find.byType(type));

  final spans = <InlineSpan>[
    for (final text in tester.widgetList<RichText>(all(RichText))) text.text,
    for (final text in tester.widgetList<SelectableText>(all(SelectableText)))
      ?text.textSpan,
  ];

  return [
    for (final span in spans)
      if (_yellowIn(span) case final yellow when yellow.isNotEmpty) yellow,
  ];
}

String _yellowIn(InlineSpan root) {
  final buffer = StringBuffer();
  root.visitChildren((span) {
    if (span is TextSpan &&
        span.style?.backgroundColor == RenderedMarkdown.playingColor) {
      buffer.write(span.text ?? '');
    }
    return true;
  });
  return buffer.toString();
}
