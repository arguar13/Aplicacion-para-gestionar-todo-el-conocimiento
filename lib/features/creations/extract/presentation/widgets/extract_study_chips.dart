import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/extract/presentation/extract_marking.dart';
import 'package:sinapsis/features/creations/extract/presentation/providers/extract_providers.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_original_study_providers.dart';
import 'package:sinapsis/features/processed/presentation/widgets/original/original_study_bar.dart';
import 'package:sinapsis/features/reading/presentation/frame/reading_ai_row.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La extracción que muestra lo de [kind]: el resumen, la síntesis o —las
/// palabras clave, que van en rosa sobre él— el texto completo.
StudyCreationKind extractKindShowing(StudyMarkKind kind) => switch (kind) {
  StudyMarkKind.summary => StudyCreationKind.summary,
  StudyMarkKind.synthesis => StudyCreationKind.synthesis,
  StudyMarkKind.keyword => StudyCreationKind.fullText,
};

/// Cómo está una de las tres —el resumen, la síntesis o las palabras clave—
/// en los documentos de una lectura: cuánto tiene marcado
/// entre todos, si la IA lo está marcando —y por dónde va—, cuáles no tienen
/// nada y, en las palabras clave, si se ven.
@immutable
class ExtractStudyState {
  const ExtractStudyState({
    required this.count,
    required this.progress,
    required this.missing,
    required this.shown,
  });

  final int count;

  /// De 0 a 100 mientras la IA marca alguno; `null` si no.
  final int? progress;

  /// Los documentos listos que no tienen nada de esto.
  final List<ExtractSection> missing;

  /// Si se ve: las palabras clave, en todos; lo demás, siempre.
  final bool shown;
}

/// Lo de [kind] en los documentos de [read], mirado en vivo.
ExtractStudyState watchExtractStudy(
  WidgetRef ref,
  ExtractRead read,
  StudyMarkKind kind,
) => _studyOf(ref.watch, read, kind);

/// Lo de [kind] en los documentos de [read], con [look] —mirar en vivo o
/// leer una vez—.
ExtractStudyState _studyOf(
  T Function<T>(ProviderListenable<T> provider) look,
  ExtractRead read,
  StudyMarkKind kind,
) {
  var count = 0;
  int? progress;
  var shown = true;
  final missing = <ExtractSection>[];
  for (final id in read.documentIds) {
    final section = look(
      extractSectionProvider((kind: extractKindShowing(kind), documentId: id)),
    );
    final own = section.own;
    if (own == null) continue;
    final analysis = look(studyAnalysisProvider(own.key));
    if (analysis is StudyAnalysisRunning) {
      progress ??= analysis.progress?.percent ?? 0;
    }
    if (section.status != ExtractSectionStatus.ready) continue;
    final marks = section.study.of(kind).length;
    count += marks;
    if (marks == 0) missing.add(section);
    if (kind == StudyMarkKind.keyword && !section.keywordsShown) shown = false;
  }
  return ExtractStudyState(
    count: count,
    progress: progress,
    missing: missing,
    shown: shown,
  );
}

/// Toca lo de [kind] en una lectura de texto (F47, paso 1): **un toque para
/// crearlo o verlo**, como las fichas del original.
///
/// - **Si ningún documento lo tiene**, lo marca con la IA en los documentos
///   mismos, después de decir con qué modelo y cuánto consume (la máquina de
///   M5 y M8, la de «Marcar con IA» del visor).
/// - **Si lo tiene**: el resumen o la síntesis se abren en su lector —el
///   mismo marco, sobre los mismos documentos—, salvo que sea lo que se está
///   leyendo; las palabras clave, que van en rosa sobre el texto, se ocultan
///   o se muestran en todos, y queda recordado por documento (la misma
///   preferencia que el original).
/// - **Mientras la IA marca**, nada: la ficha dice por dónde va, y el visor
///   tiene la franja con «Parar».
Future<void> tapExtractStudy(
  BuildContext context,
  WidgetRef ref,
  ExtractRead read,
  StudyMarkKind kind,
) async {
  final state = _studyOf(ref.read, read, kind);
  if (state.progress != null) return;
  if (state.count == 0) {
    if (state.missing.isEmpty) return;
    final confirmed = await showExtractMarkSheet(
      context,
      kind: kind,
      sections: state.missing,
    );
    if (!confirmed || !context.mounted) return;
    await markExtractWithAi(ref, context, kind: kind, sections: state.missing);
    return;
  }
  if (kind == StudyMarkKind.keyword) {
    for (final id in read.documentIds) {
      await ref
          .read(processedOriginalHiddenProvider(id).notifier)
          .setHidden(StudyMarkKind.keyword, hidden: state.shown);
    }
    return;
  }
  final showing = extractKindShowing(kind);
  if (showing == read.kind) return;
  unawaited(context.push(RoutePaths.extractReading(showing, read.documentIds)));
}

/// Las fichas Resumir · Sintetizar · Palabras clave de la fila de IA de una
/// lectura de texto (F47, paso 1): el texto extraído, el resumen o la síntesis
/// de uno o varios documentos procesados. Las mismas fichas que el original
/// —el punto de color, el estado y el avance—, sobre los documentos mismos:
/// lo marcado acá se ve en el original, y al revés. Ver [tapExtractStudy].
class ExtractStudyChips extends ConsumerWidget {
  const ExtractStudyChips({
    required this.read,
    this.trailing = const [],
    super.key,
  });

  final ExtractRead read;

  /// Lo que va después, en la misma fila: Preguntar a la IA y Podcast.
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return ReadingAiStrip(
      key: const Key('extract-study-chips'),
      children: [
        for (final kind in StudyMarkKind.values)
          Builder(
            builder: (context) {
              final state = watchExtractStudy(ref, read, kind);
              final reading =
                  state.count > 0 && extractKindShowing(kind) == read.kind;
              return StudyChip.sized(
                key: Key('extract-study-${kind.name}'),
                kind: kind,
                count: state.count,
                shown: state.shown,
                progress: state.progress,
                stateLabel: kind != StudyMarkKind.keyword && reading
                    ? l10n.f47P1ChipReading
                    : null,
                onTap: () =>
                    unawaited(tapExtractStudy(context, ref, read, kind)),
              );
            },
          ),
        ...trailing,
      ],
    );
  }
}
