import 'package:drift/drift.dart' show Variable;
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/search_index.dart';
import 'package:sinapsis/core/domain/services/vocabulary_normalizer.dart';

/// Cuántos chunks contienen cada palabra de [rawInput], sin buscarlos.
///
/// Lo dice el propio índice: `chunk_vocab` guarda en cuántos chunks aparece
/// cada palabra, y consultarlo cuesta una búsqueda en un árbol, no un recorrido
/// de las coincidencias (0 a 6 ms en 312.793 chunks, contra 137 ms de ordenar
/// una palabra frecuente por relevancia).
///
/// Cada palabra se cuenta como prefijo, igual que en la búsqueda real
/// (`buildSearchQuery` le agrega `*`).
///
/// Es una cota y no una cuenta exacta: un chunk con dos palabras que empiezan
/// igual se cuenta dos veces. Alcanza para lo que se usa —decidir si ordenar
/// por relevancia vale su costo—, y si se pasa de largo, el resultado sigue
/// siendo correcto: solo cambia cuánto se tarda.
Future<List<({String match, int hits})>> estimateTermHits(
  AppDatabase db,
  String rawInput,
) async {
  final estimates = <({String match, int hits})>[];
  for (final (:term, :match) in searchTerms(rawInput)) {
    final folded = normalizeVocabularyLabel(term);
    if (folded.isEmpty) continue;
    final row = await db
        .customSelect(
          'SELECT COALESCE(SUM(doc), 0) AS n FROM chunk_vocab '
          'WHERE term >= ? AND term < ?',
          variables: [
            Variable.withString(folded),
            // El primer texto que ya no empieza por [folded].
            Variable.withString('$folded\u{10FFFF}'),
          ],
        )
        .getSingle();
    estimates.add((match: match, hits: row.read<int>('n')));
  }
  return estimates;
}
