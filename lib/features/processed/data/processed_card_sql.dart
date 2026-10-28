import 'package:sinapsis/features/processed/domain/services/processed_card_text.dart';

/// La condición SQL de que el elemento [itemId] —una columna o expresión, como
/// `i.id`— sea un documento procesado con texto del que salgan tarjetas (F41,
/// decisión I): alguna parte no vacía de una sección de las tarjetas
/// (`isCardSection`). Es la misma regla que `buildProcessedCardText`, dicha en
/// SQL para contar sin leer el texto.
String processedHasCardTextSql(String itemId) {
  final sections = [
    for (final section in cardSections) "'${section.name}'",
  ].join(', ');
  return 'EXISTS (SELECT 1 FROM processed_parts studied '
      'WHERE studied.document_id = $itemId '
      'AND studied.section IN ($sections) '
      'AND length(trim(studied.content)) > 0)';
}
