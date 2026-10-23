import 'package:flutter/foundation.dart';

/// Qué se marca en el documento que se descarga (F38): se pueden combinar.
///
/// También sirve para decir qué de esas cuatro cosas hay para marcar: ver
/// `availableMarkedOptions`.
@immutable
class MarkedDocumentOptions {
  const MarkedDocumentOptions({
    this.summary = false,
    this.synthesis = false,
    this.keywords = false,
    this.myHighlights = false,
  });

  /// Las oraciones del resumen.
  final bool summary;

  /// Las oraciones de la síntesis.
  final bool synthesis;

  /// Las palabras clave.
  final bool keywords;

  /// Lo que la persona subrayó a mano.
  final bool myHighlights;

  bool get isEmpty => !summary && !synthesis && !keywords && !myHighlights;

  MarkedDocumentOptions copyWith({
    bool? summary,
    bool? synthesis,
    bool? keywords,
    bool? myHighlights,
  }) => MarkedDocumentOptions(
    summary: summary ?? this.summary,
    synthesis: synthesis ?? this.synthesis,
    keywords: keywords ?? this.keywords,
    myHighlights: myHighlights ?? this.myHighlights,
  );

  /// Lo que hay en las dos, para quedarse solo con lo que hay para marcar.
  MarkedDocumentOptions intersect(MarkedDocumentOptions other) =>
      MarkedDocumentOptions(
        summary: summary && other.summary,
        synthesis: synthesis && other.synthesis,
        keywords: keywords && other.keywords,
        myHighlights: myHighlights && other.myHighlights,
      );

  /// Lo elegido dicho en una frase, para el nombre del archivo: «resumen»,
  /// «resumen y mis resaltados», «resumen, síntesis y palabras clave».
  String get fileLabel {
    final parts = [
      if (summary) 'resumen',
      if (synthesis) 'síntesis',
      if (keywords) 'palabras clave',
      if (myHighlights) 'mis resaltados',
    ];
    return switch (parts.length) {
      0 => '',
      1 => parts.single,
      _ => '${parts.sublist(0, parts.length - 1).join(', ')} y ${parts.last}',
    };
  }

  @override
  bool operator ==(Object other) =>
      other is MarkedDocumentOptions &&
      other.summary == summary &&
      other.synthesis == synthesis &&
      other.keywords == keywords &&
      other.myHighlights == myHighlights;

  @override
  int get hashCode => Object.hash(summary, synthesis, keywords, myHighlights);
}
