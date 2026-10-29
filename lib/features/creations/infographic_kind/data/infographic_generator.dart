import 'package:sinapsis/features/creations/data/services/creation_illustration_store.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_material.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/domain/services/creation_generator.dart';
import 'package:sinapsis/features/creations/domain/services/structured_writer.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic.dart';
import 'package:sinapsis/features/creations/infographic_kind/data/infographic_illustrator.dart';
import 'package:sinapsis/features/creations/infographic_kind/domain/infographic_content.dart';
import 'package:sinapsis/features/creations/infographic_kind/domain/infographic_illustration_plan.dart';
import 'package:sinapsis/features/creations/infographic_kind/domain/infographic_options.dart';
import 'package:sinapsis/features/creations/infographic_kind/domain/infographic_prompts.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';

/// Genera una infografía (F43, paso 12): la IA escribe la lámina —el JSON de
/// `infographicJsonSchemaPrompt`— y, si se pidieron, se dibujan sus
/// ilustraciones con IA.
///
/// - **Las opciones de la hoja** deciden lo que se escribe: el detalle
///   (cuántos bloques y de qué peso), la orientación, el estilo («Automático»
///   le pide a la IA que sugiera uno; con ilustraciones, de los ilustrados) y
///   la descripción de la persona. El dibujo lo pone la app, y cambiar el
///   diseño después no vuelve a la IA (decisión G).
/// - **Lo largo, por partes** (`StructuredWriter`): cada parte da sus mejores
///   bloques, y el paso de unir elige y ordena los mejores de todas.
/// - **Las ilustraciones**, las que muestra el estilo
///   (`InfographicIllustrationPlan`), hasta las que estimó el aviso, con la
///   cuenta del aviso (`InfographicIllustrator`). Las que no salen no hacen
///   fallar la lámina: quedan dibujadas por la app, con su porqué.
/// - **El avance**: el texto hasta el 70 %, y cada ilustración su parte del
///   resto, en el paso «Dibujando las ilustraciones».
/// - **Volver a generar** borra las ilustraciones de la lámina anterior que
///   la nueva ya no usa.
class InfographicGenerator extends CreationGenerator {
  const InfographicGenerator({required this.illustrator, required this.store});

  final InfographicIllustrator illustrator;
  final CreationIllustrationStore Function() store;

  /// Hasta dónde llega el avance con el texto, si después se dibuja.
  static const textShare = 0.7;

  /// Lo que ocupan la instrucción y el esquema, que es largo (los ocho tipos
  /// de bloque y los nombres de los íconos).
  static const instructionTokens = 1800;

  @override
  StudyCreationKind get kind => StudyCreationKind.infographic;

  @override
  int maxOutputTokens(CreationJob job) => infographicOutputTokens(job.options);

  @override
  CreationBudget budgetFor(CreationJob job, int contextTokens) =>
      CreationBudget(
        contextTokens: contextTokens,
        reservedOutputTokens: maxOutputTokens(job),
        instructionTokens: instructionTokens,
      );

  @override
  Future<CreationOutput> generate(
    CreationJob job,
    CreationMaterial material,
    StructuredWriter writer,
    CreationProgressReport progress,
  ) async {
    final options = job.options;
    final design = infographicDesignOf(options);
    final budget = infographicWantsIllustrations(options)
        ? infographicIllustrationsFor(options)
        : 0;
    final share = budget > 0 ? textShare : 1.0;
    final description = options[CreationOptionKeys.description];

    final sheet = await writer.writeStructured(
      StructuredRequest<Infographic>(
        task: InfographicPrompts.task(design, illustrations: budget),
        schema: InfographicPrompts.schema(design.detail),
        material: material,
        budget: budgetFor(job, writer.contextTokens),
        maxOutputTokens: maxOutputTokens(job),
        parse: InfographicPrompts.parse,
        parsePartial: InfographicPrompts.parsePart,
        partTask: InfographicPrompts.partTask(design, illustrations: budget),
        mergeTask: InfographicPrompts.mergeTask(design, illustrations: budget),
        partMaxOutputTokens: InfographicPrompts.partOutputTokens,
        languageCode: job.languageCode,
        guidance: description is String ? description : null,
        cancellation: job.cancellation,
        onProgress: (value, step) => progress(value * share, step),
      ),
    );
    if (job.cancellation.isCancelled) throw const CreationCancelledException();

    var content = InfographicContent(sheet: sheet);
    if (budget > 0) {
      final slots = InfographicIllustrationPlan.slotsFor(
        sheet,
        design,
      ).take(budget).toList();
      progress(share, CreationStep.illustrating);
      content = await illustrator.illustrate(
        creationId: job.creation.id,
        content: content,
        design: design,
        slots: slots,
        accountId: _accountIdOf(options),
        cancellation: job.cancellation,
        onProgress: (done, total) => progress(
          share + (1 - share) * done / total,
          CreationStep.illustrating,
        ),
      );
    }

    await _forgetPrevious(job.creation, content.sheet);
    progress(1, CreationStep.finishing);
    return CreationOutput(
      title: content.sheet.title,
      // La versión es la 1 (`InfographicContent.version`), la de fábrica.
      content: content.encode(),
    );
  }

  static String? _accountIdOf(Map<String, Object?> options) {
    final id = options[CreationOptionKeys.imageAccountId];
    return id is String && id.isNotEmpty ? id : null;
  }

  /// Borra las ilustraciones de lo que [creation] tenía antes —al volver a
  /// generarla— que [sheet] ya no nombra.
  Future<void> _forgetPrevious(
    StudyCreation creation,
    Infographic sheet,
  ) async {
    final before = creation.content;
    if (before == null || before.isEmpty) return;
    final kept = InfographicIllustrationPlan.references(sheet);
    final previous = InfographicIllustrationPlan.references(
      InfographicContent.decode(before).sheet,
    );
    final files = store();
    for (final reference in previous.difference(kept)) {
      try {
        await files.delete(reference);
        // Un archivo viejo que no se pudo borrar no le quita nada a la lámina
        // nueva.
        // ignore: avoid_catches_without_on_clauses
      } catch (_) {}
    }
  }
}
