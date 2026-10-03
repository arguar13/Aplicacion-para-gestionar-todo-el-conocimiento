import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/ai_organize/domain/entities/ai_run.dart';
import 'package:sinapsis/features/ai_organize/presentation/widgets/ai_presentation.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

/// Cómo se dice una cuenta de la IA (F27).
void main() {
  final es = AppLocalizationsEs();

  test('cada contador de la cuenta se dice: con uno de cada cosa, hay una '
      'parte por cada una', () {
    const all = AiRunTally(
      relations: 1,
      flashcards: 1,
      properties: 1,
      spaces: 1,
      referenceFields: 1,
      topicPlacements: 1,
      mapNotes: 1,
    );

    expect(aiTallyParts(es, all), hasLength(all.total));
  });

  test('los ceros no se dicen', () {
    expect(aiTallyParts(es, const AiRunTally(flashcards: 2)), ['2 tarjetas']);
    expect(aiTallyText(es, const AiRunTally()), isEmpty);
  });

  test('las etiquetas que la IA ubicó en el árbol se cuentan aparte de las que '
      'puso', () {
    expect(
      aiTallyText(es, const AiRunTally(properties: 3, topicPlacements: 2)),
      '3 etiquetas y propiedades · 2 etiquetas ubicadas en el árbol',
    );
  });

  test('una nota mapa se dice entera', () {
    expect(aiTallyText(es, const AiRunTally(mapNotes: 1)), '1 nota mapa');
  });
}
