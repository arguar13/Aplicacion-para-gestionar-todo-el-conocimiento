import 'dart:math' as math;

import 'package:sinapsis/features/creations/domain/entities/creation_material.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/domain/services/creation_generator.dart';
import 'package:sinapsis/features/creations/domain/services/structured_writer.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_check.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_json.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_options.dart';
import 'package:sinapsis/features/creations/podcast/domain/podcast_prompt.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';

/// Lo que se le deja en la ventana a la instrucción de un podcast: la tarea
/// con sus reglas de citas, cómo terminó la vuelta anterior y el esquema.
const kPodcastInstructionTokens = 900;

/// Cuántos tokens escribe la IA por palabra dicha, con todo lo que la rodea:
/// la cita que la sostiene y el JSON del tramo. Con esto se sabe cuántas
/// palabras entran en una respuesta.
const kPodcastTokensPerWord = 2.2;

/// Cuántas palabras del podcast da, como mucho, cada palabra del material
/// leído: más que esto ya es rellenar —repetir, o decir lo que no está—.
const kPodcastWordsPerMaterialWord = 1.5;

/// Lo menos que se le pide a un podcast, aunque el material sea muy corto.
const kPodcastMinWords = 40;

/// Cuántas vueltas, como mucho: un Largo con una ventana chica.
const kPodcastMaxRounds = 12;

/// Las palabras a las que apunta un podcast de [requested] palabras cuando el
/// material leído tiene [materialWords]: las pedidas, salvo que el material
/// no dé para tanto sin rellenar ([kPodcastWordsPerMaterialWord]). El visor
/// lo dice: «el material alcanzó para unos N minutos».
int podcastTargetWords(int requested, int materialWords) => math.min(
  requested,
  math.max(
    kPodcastMinWords,
    (materialWords * kPodcastWordsPerMaterialWord).round(),
  ),
);

/// En cuántas vueltas se escribe un guion de [targetWords] palabras si cada
/// respuesta puede tener [replyTokens]: las que hagan falta para que cada una
/// entre aunque se pase hasta el [kPodcastMaxPercent] por ciento de lo
/// pedido.
int podcastRoundsFor(int targetWords, int replyTokens) {
  final perRound =
      replyTokens / kPodcastTokensPerWord * 100 / kPodcastMaxPercent;
  return (targetWords / math.max(1, perRound)).ceil().clamp(
    1,
    kPodcastMaxRounds,
  );
}

/// Quien escribe el guion de un podcast (F47, punto 5 del plan; decisión E: una
/// creación más de «Lo creado», por la misma cola, con el mismo retome y el
/// mismo servicio en primer plano que las de F43). Lo escribe la IA de turno
/// —la de Ajustes; con Gemma, todo en el teléfono— con
/// `StructuredWriter.writeStructured`, y lo comprueba la app ([PodcastChecker])
/// antes de guardarlo.
///
/// - **La duración, en palabras**: la pedida a [kPodcastWordsPerMinute], o
///   menos si el material no da ([podcastTargetWords]). Lo que escribe cada
///   vuelta se cuenta, y una que queda fuera de [podcastWordRange] se le
///   devuelve a la IA para que la corrija, con el porqué.
/// - **Por vueltas**: un guion que no entra en una respuesta del modelo se
///   escribe en varias ([podcastRoundsFor]): la primera abre, la última
///   cierra, y cada una sigue donde quedó la anterior. Por partes, cada vuelta
///   lee su tramo del material, en orden.
/// - **Comprobado**: cada vuelta pasa por [PodcastChecker] —las citas tienen
///   que estar en el material; un tramo sin cita, con citas inventadas o con
///   una cifra que no está, se quita y queda anotado—. En la conversación
///   tienen que hablar las dos voces.
class PodcastGenerator extends CreationGenerator {
  const PodcastGenerator();

  /// Lo más que escribe una vuelta: un Largo entero con un modelo grande.
  static const int replyTokens = 5600;

  /// Lo menos que se le deja escribir a una vuelta.
  static const int minReplyTokens = 500;

  /// Lo más que escribe el borrador de una parte, por partes.
  static const int partReplyTokens = 1400;

  /// Cuánto de la ventana puede ocupar la respuesta: con Gemma (2048 tokens)
  /// quedan ~900 para escribir y lo demás para leer.
  static const double windowShare = 0.45;

  @override
  StudyCreationKind get kind => StudyCreationKind.podcast;

  @override
  int maxOutputTokens(CreationJob job) => replyTokens;

  /// Lo que escribe una vuelta con una ventana de [contextTokens].
  static int replyTokensFor(int contextTokens) => math.max(
    minReplyTokens,
    math.min(replyTokens, (contextTokens * windowShare).floor()),
  );

  @override
  CreationBudget budgetFor(CreationJob job, int contextTokens) =>
      CreationBudget(
        contextTokens: contextTokens,
        reservedOutputTokens: replyTokensFor(contextTokens),
        instructionTokens: kPodcastInstructionTokens,
      );

  @override
  Future<CreationOutput> generate(
    CreationJob job,
    CreationMaterial material,
    StructuredWriter writer,
    CreationProgressReport progress,
  ) async {
    final format = PodcastFormat.of(job.options);
    final length = PodcastLength.of(job.options);
    final focus = job.options[CreationOptionKeys.topic];
    final reply = replyTokensFor(writer.contextTokens);
    final materialWords = material.readings.fold(
      0,
      (sum, r) => sum + countPodcastWords(r.text),
    );
    final target = podcastTargetWords(length.targetWords, materialWords);
    final rounds = podcastRoundsFor(target, reply);
    final perRound = (target / rounds).ceil();
    final budget = budgetFor(job, writer.contextTokens);

    var title = '';
    final written = <List<PodcastSegment>>[];
    final discarded = <PodcastDiscard>[];
    String? previous;
    for (var round = 0; round < rounds; round++) {
      if (job.cancellation.isCancelled) {
        throw const CreationCancelledException();
      }
      final slice = podcastRoundMaterial(material, round, rounds);
      final checker = PodcastChecker(slice.readings, format: format);
      final partsInSlice = slice.mode.isSingle ? 1 : slice.parts.length;
      final result = await writer.writeStructured(
        StructuredRequest<_Round>(
          task: podcastTask(
            format: format,
            words: perRound,
            round: round,
            rounds: rounds,
            previous: previous,
            sharedMaterial: material.mode.isSingle,
          ),
          partTask: podcastPartTask(
            format: format,
            words: math.max(60, (perRound / partsInSlice).ceil()),
          ),
          mergeTask: podcastMergeTask(
            format: format,
            words: perRound,
            round: round,
            rounds: rounds,
            previous: previous,
          ),
          schema: podcastSchemaPrompt(format),
          material: slice,
          budget: budget,
          maxOutputTokens: reply,
          partMaxOutputTokens: math.min(reply, partReplyTokens),
          parse: (json) => _readRound(json, checker, format, perRound),
          parsePartial: _readPart,
          guidance: focus is String ? focus : null,
          languageCode: job.languageCode,
          cancellation: job.cancellation,
          onProgress: (done, step) => progress((round + done) / rounds, step),
        ),
      );
      if (round == 0) title = result.title;
      written.add(result.check.segments);
      discarded.addAll(result.check.discarded);
      previous = _ending(result.check.segments);
    }
    if (job.cancellation.isCancelled) throw const CreationCancelledException();
    progress(1, CreationStep.finishing);

    final podcast = Podcast(
      title: title.isNotEmpty
          ? title
          : material.sources.isEmpty
          ? ''
          : material.sources.first.title,
      format: format,
      length: length,
      segments: joinPodcastRounds(written),
      requestedWords: length.targetWords,
      targetWords: target,
      discarded: discarded,
    );
    return CreationOutput(
      title: podcast.title,
      // La versión 1 del esquema (`PodcastJson.contentVersion`): la de
      // fábrica de `CreationOutput`.
      content: PodcastJson.encodeString(podcast),
    );
  }
}

/// Lo que [round] de [rounds] lee de [material]: de una vez, todo —cada vuelta
/// trata su parte, en orden, como se lo dice la tarea—; por partes, su tramo
/// de las partes, en orden. Si hay más vueltas que partes, cada parte la leen
/// las vueltas seguidas que le tocan; una sola parte va de una vez.
CreationMaterial podcastRoundMaterial(
  CreationMaterial material,
  int round,
  int rounds,
) {
  if (material.mode.isSingle || rounds <= 1) return material;
  final parts = material.parts;
  if (parts.isEmpty) return material;
  final from = (round * parts.length / rounds).floor();
  final to = math.max(from + 1, ((round + 1) * parts.length / rounds).floor());
  final slice = parts.sublist(from, math.min(to, parts.length));
  final ids = {for (final p in slice) p.documentId};
  final sources = [
    for (final source in material.sources)
      if (ids.contains(source.documentId))
        CreationMaterialSource(
          documentId: source.documentId,
          title: source.title,
          chars: [
            for (final p in slice)
              if (p.documentId == source.documentId) p.text.length,
          ].fold(0, (sum, n) => sum + n),
        ),
  ];
  if (slice.length == 1) {
    return CreationMaterial(
      mode: CreationMaterialMode.fullText,
      text: slice.single.text,
      sources: sources,
      sourceStarts: const [0],
    );
  }
  return CreationMaterial(
    mode: CreationMaterialMode.byParts,
    parts: slice,
    partsBase: material.partsBase,
    totalParts: slice.length,
    sources: sources,
  );
}

/// Una vuelta leída y comprobada.
class _Round {
  const _Round(this.title, this.check);

  final String title;
  final PodcastCheck check;
}

/// Lee y comprueba una vuelta; lanza [FormatException] con lo que se le dice
/// a la IA para que la corrija.
_Round _readRound(
  Object? json,
  PodcastChecker checker,
  PodcastFormat format,
  int words,
) {
  final draft = PodcastJson.readDraft(json);
  if (draft.segments.isEmpty) {
    throw const FormatException(
      'El guion no trae ningún tramo con "speaker" y "text" en "segments".',
    );
  }
  final check = checker.check(draft.segments);
  final discarded = check.discarded.isEmpty
      ? ''
      : ' Se quitaron ${check.discarded.length} tramos porque no tenían una '
            'cita copiada tal cual del material, o decían algo —una cifra, una '
            'cita— que no está en él: cada tramo de datos va con una cita '
            'literal.';
  if (check.segments.isEmpty) {
    throw FormatException('No quedó ningún tramo que se sostenga.$discarded');
  }
  if (format.speakerCount == 2 && check.speakers.length < 2) {
    throw FormatException(
      'Es una conversación: tienen que hablar las dos voces, la "A" y la "B", '
      'turnándose.$discarded',
    );
  }
  final (lo, hi) = podcastWordRange(words);
  final said = check.words;
  if (said < lo || said > hi) {
    throw FormatException(
      'Quedó de $said palabras dichas, y tiene que tener entre $lo y $hi '
      '(unas $words).$discarded',
    );
  }
  return _Round(draft.title, check);
}

/// Lee el borrador de una parte, por partes: alcanza con que tenga tramos;
/// se comprueba lo que quede después de unir.
Object? _readPart(Object? json) {
  if (PodcastJson.readDraft(json).segments.isEmpty) {
    throw const FormatException(
      'El borrador no trae ningún tramo con "speaker" y "text" en "segments".',
    );
  }
  return json;
}

/// Cómo terminó una vuelta: sus dos últimos tramos, para que la que sigue no
/// lo repita. Corto, para no gastar la ventana.
String? _ending(List<PodcastSegment> segments) {
  if (segments.isEmpty) return null;
  final tail = segments
      .skip(math.max(0, segments.length - 2))
      .map((s) => s.text)
      .join(' ');
  return tail.length <= 300 ? tail : '…${tail.substring(tail.length - 299)}';
}
