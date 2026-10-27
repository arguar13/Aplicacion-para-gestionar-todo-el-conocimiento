import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_segments.dart';

/// Un texto que se ofrece **entero** para leer en voz alta —un libro, un PDF,
/// una página web— y cómo se llama: el `id` del documento, su `title`, el
/// `sourceKey` de sus pedazos y si `content` es Markdown.
typedef ReadableText = ({
  String id,
  String title,
  String sourceKey,
  String content,
  bool markdown,
});

/// Un [ReadableText], partido en lo que el lector flotante lee de una vez
/// (F25): lo que se lee con «Todo». Lo estudiado se le suma después —ver
/// [ReadableDocument.withScopes]—.
///
/// Un texto corto se parte en el momento; uno largo, en otro hilo —ver
/// [buildReadableSegmentsOff]—: partir «Don Quijote» (2 MB) en líneas lleva
/// más de medio segundo en una computadora, y en el hilo de la pantalla el
/// visor se congelaba al abrirse. Mientras se parte se ofrece `null`: el botón
/// redondo aparece cuando está listo, una fracción de segundo después, sin
/// trabar nada. Se parte una vez por texto mientras alguien lo mire: el mismo
/// libro en el lector y en el detalle a la vez es una sola cuenta.
final readableTextProvider = NotifierProvider.autoDispose
    .family<ReadableTextNotifier, ReadableDocument?, ReadableText>(
      ReadableTextNotifier.new,
    );

/// Ver [readableTextProvider].
class ReadableTextNotifier
    extends AutoDisposeFamilyNotifier<ReadableDocument?, ReadableText> {
  @override
  ReadableDocument? build(ReadableText text) {
    ReadableDocument documentOf(List<ReadableSegment> segments) =>
        ReadableDocument(id: text.id, title: text.title, segments: segments);

    if (text.content.length <= kSegmentsInlineChars) {
      return documentOf(
        buildReadableSegments(
          text.content,
          sourceKey: text.sourceKey,
          markdown: text.markdown,
        ),
      );
    }
    var listened = true;
    ref.onDispose(() => listened = false);
    unawaited(
      buildReadableSegmentsOff(
        text.content,
        sourceKey: text.sourceKey,
        markdown: text.markdown,
      ).then((segments) {
        if (listened) state = documentOf(segments);
      }),
    );
    return null;
  }
}
