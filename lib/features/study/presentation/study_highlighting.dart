import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/domain/services/study_keyword_toggle.dart';
import 'package:sinapsis/features/study/domain/services/study_words.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Cuál de los dos resaltados de oraciones se ve (F36): uno o el otro, nunca
/// los dos encima.
enum StudyLayer {
  summary(StudyMarkKind.summary),
  synthesis(StudyMarkKind.synthesis);

  const StudyLayer(this.kind);

  final StudyMarkKind kind;
}

/// Qué se ve de lo estudiado de un texto (F36): lo mismo en el detalle, en
/// «Leer como libro» y en «Texto extraído».
@immutable
class StudyView {
  const StudyView({this.layer, this.keywords = false, this.picking = false});

  /// El resumen o la síntesis; `null`, ninguno.
  final StudyLayer? layer;

  /// Si se ven las palabras clave.
  final bool keywords;

  /// Si tocar una palabra la agrega o la saca de las palabras clave. Mientras
  /// tanto se ven, estén o no prendidas.
  final bool picking;

  bool get showsKeywords => keywords || picking;

  /// Las oraciones a las que pertenecen las palabras clave que se ven: las
  /// del resaltado prendido o, sin ninguno, las de los dos.
  Set<StudyMarkKind> get sentenceKinds => switch (layer) {
    final layer? => {layer.kind},
    null => const {StudyMarkKind.summary, StudyMarkKind.synthesis},
  };

  StudyView copyWith({
    StudyLayer? Function()? layer,
    bool? keywords,
    bool? picking,
  }) => StudyView(
    layer: layer == null ? this.layer : layer(),
    keywords: keywords ?? this.keywords,
    picking: picking ?? this.picking,
  );

  @override
  bool operator ==(Object other) =>
      other is StudyView &&
      other.layer == layer &&
      other.keywords == keywords &&
      other.picking == picking;

  @override
  int get hashCode => Object.hash(layer, keywords, picking);
}

/// Qué se ve de lo estudiado del texto de una forma (F36).
final studyViewProvider = StateProvider.autoDispose.family<StudyView, String>(
  (ref, renditionId) => const StudyView(),
);

/// Los colores de resaltador (F36): verde el resumen, celeste la síntesis y
/// rosa las palabras clave. El amarillo es de lo que se lee en voz alta.
///
/// La letra va oscura sobre los tres, también en modo oscuro: como un
/// resaltador sobre papel, se lee igual en los dos.
@immutable
class StudyPalette {
  const StudyPalette._({
    required this.summary,
    required this.synthesis,
    required this.keyword,
  });

  factory StudyPalette.of(Brightness brightness) =>
      brightness == Brightness.dark ? _dark : _light;

  static const _light = StudyPalette._(
    summary: Color(0xFFC8F2C2),
    synthesis: Color(0xFFBDE6FF),
    keyword: Color(0xFFFFB3D9),
  );

  static const _dark = StudyPalette._(
    summary: Color(0xFF9BE08F),
    synthesis: Color(0xFF8FD3FF),
    keyword: Color(0xFFFF8CC6),
  );

  final Color summary;
  final Color synthesis;
  final Color keyword;

  /// La letra sobre cualquiera de los tres.
  static const ink = Colors.black87;

  Color of(StudyLayer layer) => switch (layer) {
    StudyLayer.summary => summary,
    StudyLayer.synthesis => synthesis,
  };
}

/// Las capas de color de lo estudiado con lo que [view] deja ver, en
/// posiciones del texto: las oraciones del resaltado prendido debajo de los
/// subrayados de la persona y las palabras clave, en negrita, encima.
List<PaintedRange> studyPaints(
  DocumentStudy study,
  StudyView view,
  StudyPalette palette,
) {
  final layer = view.layer;
  final sentences = [
    for (final mark in study.marks)
      if (view.sentenceKinds.contains(mark.kind)) mark,
  ];
  return [
    if (layer != null)
      for (final sentence in sentences)
        PaintedRange(
          sentence.start,
          sentence.end,
          background: palette.of(layer),
          foreground: StudyPalette.ink,
        ),
    if (view.showsKeywords)
      for (final keyword in study.of(StudyMarkKind.keyword))
        if (sentences.any((s) => keyword.isWithin(s.start, s.end)))
          PaintedRange(
            keyword.start,
            keyword.end,
            background: palette.keyword,
            foreground: StudyPalette.ink,
            bold: true,
            aboveHighlights: true,
          ),
  ];
}

/// Las capas de [paints] que tocan `[start, end)`, recortadas a ese tramo y
/// contadas desde [start]: lo que cae en una página del lector.
List<PaintedRange> paintsWithin(
  List<PaintedRange> paints,
  int start,
  int end,
) => [
  for (final paint in paints)
    if (paint.end > start && paint.start < end)
      PaintedRange(
        (paint.start < start ? start : paint.start) - start,
        (paint.end > end ? end : paint.end) - start,
        background: paint.background,
        foreground: paint.foreground,
        bold: paint.bold,
        aboveHighlights: paint.aboveHighlights,
      ),
];

/// Las capas de lo estudiado del texto de [renditionId], con los colores del
/// tema, y cada cambio: lo que pintan el lector y «Texto extraído».
///
/// [brightness] fija los colores en vez del tema: la página de un PDF es
/// blanca también en modo oscuro.
List<PaintedRange> watchStudyPaints(
  WidgetRef ref,
  BuildContext context,
  String renditionId, {
  Brightness? brightness,
}) {
  final view = ref.watch(studyViewProvider(renditionId));
  if (view.layer == null && !view.showsKeywords) return const [];
  final study = ref.watch(documentStudyProvider(renditionId)).valueOrNull;
  if (study == null) return const [];
  return studyPaints(
    study,
    view,
    StudyPalette.of(brightness ?? Theme.of(context).brightness),
  );
}

/// Eligiendo palabras clave, se tocó la posición [offset] de [content]: la
/// palabra de ahí se agrega o se saca (F36). Si la oración ya tiene sus
/// cuatro, lo avisa.
Future<void> toggleStudyKeywordAt(
  WidgetRef ref,
  BuildContext context, {
  required String renditionId,
  required String content,
  required int offset,
}) async {
  final view = ref.read(studyViewProvider(renditionId));
  final study = ref.read(documentStudyProvider(renditionId)).valueOrNull;
  if (!view.picking || study == null) return;

  final repository = ref.read(studyRepositoryProvider);
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.maybeOf(context);
  void say(String message) => messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  final toggle = keywordToggleAt(
    content: content,
    study: study,
    sentenceKinds: view.sentenceKinds,
    offset: offset,
  );
  final saved = switch (toggle) {
    KeywordToggleAdd(:final word) => await repository.addKeyword(
      renditionId: renditionId,
      content: content,
      word: word,
    ),
    KeywordToggleRemove(:final markId) => await repository.removeKeyword(
      markId,
    ),
    KeywordToggleFull() => null,
    KeywordToggleNone() => null,
  };
  if (toggle is KeywordToggleFull) {
    say(l10n.studyKeywordsSentenceFull(kMaxKeywordsPerSentence));
  }
  saved?.mapLeft((failure) => say(failure.localizedMessage(l10n)));
}
