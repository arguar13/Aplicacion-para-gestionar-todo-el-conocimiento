import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/presentation/providers/creations_providers.dart';
import 'package:sinapsis/features/creations/presentation/providers/repasar_providers.dart';
import 'package:sinapsis/features/creations/report/domain/report.dart';
import 'package:sinapsis/features/creations/report/domain/report_json.dart';
import 'package:sinapsis/features/creations/report/domain/report_keywords.dart';
import 'package:sinapsis/features/creations/report/domain/report_template.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_original_study_providers.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/study/domain/services/study_words.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart'
    as study;

/// El informe guardado en el contenido de una creación —su JSON—, leído una
/// vez por contenido.
final reportOfContentProvider = Provider.autoDispose.family<Report, String?>(
  (ref, content) =>
      content == null ? const Report(title: '') : ReportJson.decode(content),
);

/// Cuántos documentos se leen, como mucho, para buscar sus palabras clave:
/// un cuaderno grande no traba el visor.
const kReportKeywordDocuments = 24;

/// Las palabras clave de las fuentes de un informe (decisión 85): las de sus
/// marcas de estudiar (F36, las mismas que el original y las vistas vivas
/// de Repasar, M8), las más marcadas primero (`rankReportKeywords`). Las de
/// un documento donde la persona las ocultó no cuentan. Vacía si ninguna
/// fuente tiene las suyas todavía.
final reportSourceKeywordsProvider = FutureProvider.autoDispose
    .family<List<String>, CreationSourceIds>((ref, key) async {
      final processed = ref.watch(processedRepositoryProvider);
      final studies = ref.watch(study.studyRepositoryProvider);
      final counts = <String, int>{};
      final shown = <String, String>{};
      for (final id in key.ids.take(kReportKeywordDocuments)) {
        if (!ref.watch(processedKeywordsShownProvider(id))) continue;
        final text = (await processed.studyTextOf(id)).getRight().toNullable();
        if (text == null) continue;
        final studied = await studies.read(text.key);
        for (final mark in studied.of(StudyMarkKind.keyword)) {
          if (mark.end > text.content.length || mark.start >= mark.end) {
            continue;
          }
          final word = text.content
              .substring(mark.start, mark.end)
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
          final folded = foldStudyWord(word);
          if (folded.isEmpty) continue;
          shown.putIfAbsent(folded, () => word);
          counts[folded] = (counts[folded] ?? 0) + 1;
        }
      }
      return [for (final folded in rankReportKeywords(counts)) shown[folded]!];
    });

/// De qué informe se buscan las palabras clave: sus fuentes y su contenido.
typedef ReportKeywordsKey = ({CreationSourceIds sources, String? content});

/// La clave de [creation] para [reportKeywordsProvider].
ReportKeywordsKey reportKeywordsKeyOf(StudyCreation creation) =>
    (sources: CreationSourceIds(creation.sourceIds), content: creation.content);

/// Las palabras clave que se pintan en un informe: las de sus fuentes y, si
/// ninguna tiene todavía, las que la IA destacó en el informe.
final reportKeywordsProvider = Provider.autoDispose
    .family<ReportKeywords, ReportKeywordsKey>((ref, key) {
      final fromSources =
          ref.watch(reportSourceKeywordsProvider(key.sources)).valueOrNull ??
          const <String>[];
      if (fromSources.isNotEmpty) return ReportKeywords(fromSources);
      final report = ref.watch(reportOfContentProvider(key.content));
      return ReportKeywords(report.keywords);
    });

/// Las plantillas propias de informes anteriores, sin repetir y la más
/// reciente primero: «Las que ya usaste», para volver a usarlas con un toque.
/// Salen de «Lo creado» mismo —lo que se pidió está en las opciones de cada
/// informe—, así que viajan con la bóveda y no hay otro guardado.
final reportUsedCustomTemplatesProvider =
    StreamProvider.autoDispose<List<String>>((ref) {
      final repository = ref.watch(studyCreationRepositoryProvider);
      return repository
          .watchByScope(const CreationScope.allProcessed())
          .map(usedReportCustomTemplates);
    });

/// Cuántas plantillas propias se ofrecen para volver a usar.
const kReportUsedTemplatesShown = 5;

/// Las plantillas propias de [creations] (con la más nueva primero), sin
/// repetir —sin mayúsculas ni tildes de más— y hasta
/// [kReportUsedTemplatesShown].
List<String> usedReportCustomTemplates(List<StudyCreation> creations) {
  final used = <String>[];
  final seen = <String>{};
  for (final creation in creations) {
    if (creation.kind != StudyCreationKind.report) continue;
    if (ReportTemplate.of(creation.options) != ReportTemplate.custom) continue;
    final text = reportCustomTemplateOf(creation.options);
    if (text.isEmpty || !seen.add(foldStudyWord(text))) continue;
    used.add(text);
    if (used.length == kReportUsedTemplatesShown) break;
  }
  return used;
}

/// Cómo se está leyendo un informe abierto: qué secciones están plegadas,
/// qué se respondió, si se pintan las palabras clave y a qué sección saltar.
/// Vive mientras el visor está abierto; lo comparten el cuerpo y los botones
/// de la barra (el índice).
@immutable
class ReportReadingState {
  const ReportReadingState({
    this.folded = const {},
    this.answers = const {},
    this.keywords,
    this.jumpTo,
    this.jumps = 0,
  });

  /// Las secciones plegadas, por su lugar.
  final Set<int> folded;

  /// Lo que se eligió en cada pregunta: `(sección, pregunta)` → la opción,
  /// por su lugar en `ReportQuestion.options`.
  final Map<(int, int), int> answers;

  /// Si se pintan las palabras clave; `null` es lo de fábrica (sí, salvo
  /// que la persona las haya ocultado en sus documentos).
  final bool? keywords;

  /// La sección a la que se pidió saltar por última vez, y cuántas veces se
  /// pidió: el cuerpo salta cada vez que [jumps] cambia.
  final int? jumpTo;
  final int jumps;

  ReportReadingState copyWith({
    Set<int>? folded,
    Map<(int, int), int>? answers,
    bool? keywords,
    int? jumpTo,
    int? jumps,
  }) => ReportReadingState(
    folded: folded ?? this.folded,
    answers: answers ?? this.answers,
    keywords: keywords ?? this.keywords,
    jumpTo: jumpTo ?? this.jumpTo,
    jumps: jumps ?? this.jumps,
  );
}

class ReportReading
    extends AutoDisposeFamilyNotifier<ReportReadingState, String> {
  @override
  ReportReadingState build(String creationId) => const ReportReadingState();

  void toggleFold(int section) {
    final folded = {...state.folded};
    if (!folded.remove(section)) folded.add(section);
    state = state.copyWith(folded: folded);
  }

  void foldAll(int sections) =>
      state = state.copyWith(folded: {for (var i = 0; i < sections; i++) i});

  void unfoldAll() => state = state.copyWith(folded: const {});

  /// Elige [option] en la pregunta [question] de [section]. Una ya
  /// respondida no cambia: la primera es la que cuenta, como en el quiz.
  void answer(int section, int question, int option) {
    if (state.answers.containsKey((section, question))) return;
    state = state.copyWith(
      answers: {...state.answers, (section, question): option},
    );
  }

  /// «Volver a intentar»: borra todas las respuestas.
  void resetAnswers() => state = state.copyWith(answers: const {});

  void setKeywords({required bool shown}) =>
      state = state.copyWith(keywords: shown);

  /// Salta a [section], desplegándola si estaba plegada.
  void jump(int section) => state = state.copyWith(
    folded: {...state.folded}..remove(section),
    jumpTo: section,
    jumps: state.jumps + 1,
  );
}

final reportReadingProvider = NotifierProvider.autoDispose
    .family<ReportReading, ReportReadingState, String>(ReportReading.new);

/// Si las palabras clave de un informe con estas fuentes se pintan de
/// entrada: sí, salvo que la persona las haya ocultado en todas (M5).
final reportKeywordsShownByDefaultProvider = Provider.autoDispose
    .family<bool, CreationSourceIds>((ref, sources) {
      if (sources.ids.isEmpty) return true;
      return sources.ids.any(
        (id) => ref.watch(processedKeywordsShownProvider(id)),
      );
    });
