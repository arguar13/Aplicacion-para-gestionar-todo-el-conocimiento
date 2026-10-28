import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/core/error/failure_messages.dart';
import 'package:sinapsis/features/organize/presentation/widgets/markdown_display.dart';
import 'package:sinapsis/features/processed/domain/services/processed_identity.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_triage_providers.dart';
import 'package:sinapsis/features/study/domain/entities/document_study.dart';
import 'package:sinapsis/features/study/domain/services/study_layers.dart';
import 'package:sinapsis/features/study/domain/services/study_pick.dart';
import 'package:sinapsis/features/study/domain/services/study_words.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Los dos resaltados de oraciones (F36). Se prenden por separado o juntos
/// (F39): juntos, la síntesis va encima del resumen —es lo más esencial—.
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
  const StudyView({
    this.summary = false,
    this.synthesis = false,
    this.keywords = false,
    this.pick,
  });

  /// Si se ve el resumen.
  final bool summary;

  /// Si se ve la síntesis.
  final bool synthesis;

  /// Si se ven las palabras clave: todas, de punta a punta (F39).
  final bool keywords;

  /// Qué se está eligiendo a mano (F36, F39): tocar una oración la pone en
  /// el resumen o en la síntesis —o la saca—, y tocar una palabra, en las
  /// palabras clave. `null`, nada: un toque es un toque.
  final StudyMarkKind? pick;

  /// Si un toque es para elegir: quien muestra el texto se lo pasa a
  /// [pickStudyAt] y no hace lo de siempre.
  bool get picking => pick != null;

  /// Eligiéndolas, las palabras clave se ven estén o no prendidas.
  bool get showsKeywords => keywords || pick == StudyMarkKind.keyword;

  /// Si se ve [layer].
  bool shows(StudyLayer layer) => switch (layer) {
    StudyLayer.summary => summary,
    StudyLayer.synthesis => synthesis,
  };

  /// Los resaltados de oraciones que se ven, de abajo hacia arriba.
  List<StudyLayer> get layers => [
    if (summary) StudyLayer.summary,
    if (synthesis) StudyLayer.synthesis,
  ];

  /// Si no se ve nada de lo estudiado.
  bool get showsNothing => !summary && !synthesis && !showsKeywords;

  /// Con [layer] prendido o apagado; lo demás, igual.
  StudyView withLayer(StudyLayer layer, {required bool on}) => copyWith(
    summary: layer == StudyLayer.summary ? on : null,
    synthesis: layer == StudyLayer.synthesis ? on : null,
  );

  StudyView copyWith({
    bool? summary,
    bool? synthesis,
    bool? keywords,
    StudyMarkKind? Function()? pick,
  }) => StudyView(
    summary: summary ?? this.summary,
    synthesis: synthesis ?? this.synthesis,
    keywords: keywords ?? this.keywords,
    pick: pick == null ? this.pick : pick(),
  );

  @override
  bool operator ==(Object other) =>
      other is StudyView &&
      other.summary == summary &&
      other.synthesis == synthesis &&
      other.keywords == keywords &&
      other.pick == pick;

  @override
  int get hashCode => Object.hash(summary, synthesis, keywords, pick);
}

/// Qué se ve de lo estudiado del texto de una forma (F36).
final studyViewProvider = StateProvider.autoDispose.family<StudyView, String>(
  (ref, renditionId) => renditionId.startsWith(kProcessedOriginalStudyKeyPrefix)
      ? kMarkedCopyStudyView
      : const StudyView(),
);

/// Cómo se abre la copia del original de un documento procesado (F41,
/// decisión H): con todo lo elegido a la vista —es lo que se fue a ver—. Sus
/// interruptores lo apagan de a uno.
const kMarkedCopyStudyView = StudyView(
  summary: true,
  synthesis: true,
  keywords: true,
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
/// posiciones del texto: las oraciones de los resaltados prendidos debajo de
/// los subrayados de la persona —la síntesis encima del resumen— y las
/// palabras clave, en negrita, encima de todo.
///
/// Las tres se prenden cada una por su lado (F39): las palabras clave que se
/// ven son todas, estén o no en una oración resaltada.
List<PaintedRange> studyPaints(
  DocumentStudy study,
  StudyView view,
  StudyPalette palette,
) {
  return [
    for (final layer in view.layers)
      for (final sentence in studySentenceMarks(study, {layer.kind}))
        PaintedRange(
          sentence.start,
          sentence.end,
          background: palette.of(layer),
          foreground: StudyPalette.ink,
        ),
    if (view.showsKeywords)
      for (final keyword in study.of(StudyMarkKind.keyword))
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
///
/// Mientras se corta del original para Procesado (F41), lleva encima los
/// cortes: así cada visor que pinta lo estudiado —el texto extraído, el
/// lector, el PDF— marca también lo cortado, sin saber de Procesado.
List<PaintedRange> watchStudyPaints(
  WidgetRef ref,
  BuildContext context,
  String renditionId, {
  Brightness? brightness,
}) {
  final shade = brightness ?? Theme.of(context).brightness;
  final cuts = watchProcessedCutPaints(ref, renditionId, brightness: shade);
  final view = ref.watch(studyViewProvider(renditionId));
  if (view.showsNothing) return cuts;
  final study = ref.watch(documentStudyProvider(renditionId)).valueOrNull;
  if (study == null) return cuts;
  final paints = studyPaints(study, view, StudyPalette.of(shade));
  return cuts.isEmpty ? paints : [...paints, ...cuts];
}

/// Eligiendo a mano, se tocó la posición [offset] de [content] (F36, F39):
/// la oración de ahí entra en el resumen o en la síntesis —o sale—, o la
/// palabra de ahí, en las palabras clave. Si la oración ya tiene sus cuatro
/// palabras clave, lo avisa.
///
/// [markdown] es el de [content] al estudiarlo: parte las oraciones igual que
/// el análisis, así lo elegido a mano y lo de la IA coinciden.
Future<void> pickStudyAt(
  WidgetRef ref,
  BuildContext context, {
  required String renditionId,
  required String content,
  required bool markdown,
  required int offset,
}) async {
  final kind = ref.read(studyViewProvider(renditionId)).pick;
  final study = ref.read(documentStudyProvider(renditionId)).valueOrNull;
  if (kind == null || study == null) return;

  final repository = ref.read(studyRepositoryProvider);
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.maybeOf(context);
  void say(String message) => messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  final toggle = studyPickAt(
    content: content,
    markdown: markdown,
    study: study,
    kind: kind,
    offset: offset,
  );
  final saved = switch (toggle) {
    StudyPickAdd(:final kind, :final start, :final end) =>
      await repository.addUserMark(
        renditionId: renditionId,
        content: content,
        kind: kind,
        start: start,
        end: end,
      ),
    StudyPickRemove(:final markId) => await repository.removeMark(markId),
    StudyPickFull() => null,
    StudyPickNone() => null,
  };
  if (toggle is StudyPickFull) {
    say(l10n.studyKeywordsSentenceFull(kMaxKeywordsPerSentence));
  }
  saved?.mapLeft((failure) => say(failure.localizedMessage(l10n)));
}
