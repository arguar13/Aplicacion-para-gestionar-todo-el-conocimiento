import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';
import 'package:sinapsis/features/study/domain/services/study_readable.dart';
import 'package:sinapsis/features/study/domain/study_target.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart';

/// Lo que se lee en voz alta con cada capa de lo estudiado del texto `text`
/// (F39), y cada cambio: la única cuenta de «qué se está leyendo» que usan la
/// tarjeta de estudiar y el detalle, y con ellos el reproductor.
///
/// Vacío mientras lo estudiado no cargó: el reproductor no ofrece elegir la
/// parte hasta saber qué hay.
final studyReadScopesProvider = Provider.autoDispose
    .family<Map<ReadScope, List<ReadableSegment>>, StudyText>((ref, text) {
      final study = ref
          .watch(documentStudyProvider(text.renditionId))
          .valueOrNull;
      if (study == null) return const {};
      return studyReadScopes(
        sourceKey: text.renditionId,
        content: text.content,
        study: study,
        markdown: text.markdown,
      );
    });
