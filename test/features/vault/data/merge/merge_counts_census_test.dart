import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// El censo de lo que la unión de bóvedas cuenta (F40).
///
/// La unión por conjuntos copia tabla por tabla, y cada tabla que copia tiene
/// que figurar en tres lugares: la cuenta del resultado (lo que se escribió),
/// la de la vista previa (lo que se escribiría) y las dos guardas que dicen
/// «no hay nada nuevo» / «no cambió nada». Cuando `dated_events` y
/// `study_marks` se sumaron a la unión, ninguno de los tres lugares se enteró:
/// una copia cuya única novedad era un hecho fechado se anunciaba como «nada
/// nuevo, no hace falta unirla».
///
/// Esta prueba recorre el código fuente —como `read_census_test.dart`— y falla
/// si una tabla de la unión no está en la lista de abajo, o si está y le falta
/// alguno de sus lugares. Lo que de verdad cuenta cada cifra lo prueban las
/// pruebas de la vista previa y de cada unión; esto dice que no se olvidó
/// ninguna.
void main() {
  /// Cada tabla que `SetUnionMerge` escribe: el campo de la vista previa que la
  /// cuenta (`null` con el motivo en [notPreviewed]) y el del resultado.
  const covered = <String, ({String? preview, String? result})>{
    'relations': (preview: 'newRelations', result: 'relationsAdded'),
    'highlights': (preview: 'newHighlights', result: 'highlightsAdded'),
    'flashcards': (preview: 'newFlashcards', result: 'flashcardsAdded'),
    'flashcard_options': (preview: null, result: 'flashcardOptionsAdded'),
    'review_log': (preview: null, result: 'reviewsAdded'),
    'merged_provenances': (preview: null, result: 'provenancesAdded'),
    'conversations': (
      preview: 'newConversations',
      result: 'conversationsAdded',
    ),
    'chat_messages': (preview: null, result: 'messagesAdded'),
    'habit_event': (preview: null, result: 'habitEventsAdded'),
    'study_marks': (preview: 'newStudyMarks', result: 'studyMarksAdded'),
    'study_analyses': (preview: null, result: null),
    'dated_events': (preview: 'newDatedEvents', result: 'datedEventsAdded'),
    'processed_documents': (preview: null, result: 'processedDocumentsAdded'),
    'processed_parts': (
      preview: 'newProcessedParts',
      result: 'processedPartsAdded',
    ),
  };

  /// Las tablas que la vista previa no cuenta aparte, y por qué. Una tabla
  /// nueva no entra acá por comodidad: tiene que decir de qué cuenta depende.
  const notPreviewed = <String, String>{
    'flashcard_options':
        'entran junto con su tarjeta, nunca solas: se cuentan en las tarjetas',
    'review_log': 'el historial de repasos de las tarjetas que entran',
    'merged_provenances': 'el rastro de dónde vino un elemento que entra',
    'chat_messages':
        'entran junto con su conversación, nunca solos: se cuentan en las '
        'conversaciones',
    'habit_event': 'el rastro mínimo de la racha: no es contenido',
    'study_analyses':
        'el análisis de un texto viaja con sus marcas de estudio: se cuenta '
        'en las marcas, y no devuelve su propia cifra',
    'processed_documents':
        'un procesado nuevo entra con su elemento: se cuenta en los elementos '
        'nuevos (y sus partes, aparte)',
  };

  /// Campos de la vista previa que no entran en «hay algo nuevo» ni son un
  /// renglón propio, y por qué.
  const previewFieldsApart = <String, String>{
    'incomingItems': 'cuántos elementos trae la copia: no es una novedad',
    'newSources': 'se suma en newItems',
    'newNotes': 'se suma en newItems',
    'commonItems': 'los que las dos tienen: no es una novedad',
    'itemsToUpdate': 'se dice en fieldsToUpdate',
    'newFilesBytes': 'el peso de newFiles',
    'filesMissingInBackup':
        'un aviso aparte: no es algo que la copia traiga a esta bóveda',
  };

  /// Campos del resultado que no entran en «no cambió nada», y por qué.
  const resultFieldsApart = <String, String>{
    'fieldsUpdated': 'se resume en itemsUpdated y los campos de los textos',
    'itemsUpdated': 'lo decide fieldsUpdated / textsUpdated',
    'valueParentsIgnored': 'lo que NO entró',
    'sourcesPending': 'lo derivado que se reintenta: no es una novedad',
    'filesMissing': 'lo que NO se pudo copiar',
    'filesDiffering': 'se queda el de acá: no cambia nada',
    'filesCopiedBytes': 'el peso de filesCopied',
  };

  String read(String path) => File(path).readAsStringSync();

  final union = read('lib/features/vault/data/merge/set_union_merge.dart');
  final merger = read('lib/features/vault/data/merge/vault_merger.dart');
  final reader = read('lib/features/vault/data/merge/vault_merge_reader.dart');
  final previewSrc = read(
    'lib/features/vault/domain/entities/vault_merge_preview.dart',
  );
  final resultSrc = read(
    'lib/features/vault/domain/entities/vault_merge_result.dart',
  );
  final lines = read(
    'lib/features/vault/presentation/widgets/vault_merge_summaries.dart',
  );

  /// Los campos enteros de una entidad freezed.
  Set<String> intFields(String source) => {
    for (final m in RegExp(
      r'(?:@Default\(0\)\s+|required\s+)int\s+(?!get)(\w+)',
    ).allMatches(source))
      m.group(1)!,
  };

  /// El cuerpo de un getter, hasta su `;`.
  String getterBody(String source, String name) {
    final start = source.indexOf('get $name');
    expect(start, isNonNegative, reason: 'no encuentro `get $name`');
    return source.substring(start, source.indexOf(';', start));
  }

  test('el detector reconoce las tablas que la unión escribe', () {
    final tables = unionTables(union);

    expect(tables, containsAll(['relations', 'study_marks', 'dated_events']));
  });

  test('toda tabla que la unión escribe está en el censo, y al revés', () {
    expect(
      unionTables(union),
      covered.keys.toSet(),
      reason:
          'una tabla nueva de la unión necesita su cifra en la vista previa y '
          'en el resultado, o el motivo por el que no',
    );
  });

  test('toda cifra que la unión devuelve llega al resultado de la fusión', () {
    final fields = setUnionResultFields(union);

    expect(fields, isNotEmpty);
    for (final field in fields) {
      expect(
        merger,
        contains('unions.$field'),
        reason:
            '`SetUnionResult.$field` se cuenta y nadie lo pasa al resultado',
      );
    }
  });

  group('cada tabla de la unión', () {
    for (final entry in covered.entries) {
      final table = entry.key;
      final (:preview, :result) = entry.value;

      test('$table: su cifra en el resultado', () {
        if (result == null) return;
        expect(intFields(resultSrc), contains(result));
        expect(merger, contains('$result: unions.'));
        expect(
          getterBody(resultSrc, 'changedNothing'),
          contains(result),
          reason: 'una fusión que solo trajo $table se diría «no cambió nada»',
        );
      });

      test('$table: su cifra en la vista previa, o el motivo', () {
        if (preview == null) {
          expect(
            notPreviewed[table],
            isNotNull,
            reason: 'la vista previa no cuenta $table: falta decir por qué',
          );
          return;
        }
        expect(notPreviewed, isNot(contains(table)));
        expect(intFields(previewSrc), contains(preview));
        expect(
          reader,
          contains('$preview:'),
          reason: 'el lector de la vista previa no llena $preview',
        );
        expect(
          getterBody(previewSrc, 'hasNothingNew'),
          contains(preview),
          reason:
              'una copia cuya única novedad es $table se diría «nada nuevo»',
        );
        expect(
          lines,
          contains('preview.$preview'),
          reason: 'la pantalla no muestra $preview',
        );
      });
    }
  });

  test(
    'todo campo de la vista previa cuenta como novedad, o dice por qué no',
    () {
      final hasNothingNew = getterBody(previewSrc, 'hasNothingNew');
      for (final field in intFields(previewSrc)) {
        if (previewFieldsApart.containsKey(field)) continue;
        expect(
          hasNothingNew,
          contains(field),
          reason: '`$field` no entra en hasNothingNew',
        );
      }
    },
  );

  test('todo campo del resultado cuenta como cambio, o dice por qué no', () {
    final changedNothing = getterBody(resultSrc, 'changedNothing');
    for (final field in intFields(resultSrc)) {
      if (resultFieldsApart.containsKey(field)) continue;
      expect(
        changedNothing,
        contains(field),
        reason: '`$field` no entra en changedNothing',
      );
    }
  });
}

/// Las tablas que `SetUnionMerge` escribe con `_union(_db.x, 'tabla', …)`.
Set<String> unionTables(String source) => {
  for (final m in RegExp(r"_union\(\s*_db\.\w+,\s*'(\w+)'").allMatches(source))
    m.group(1)!,
};

/// Los campos de `SetUnionResult`: lo que la unión cuenta.
Set<String> setUnionResultFields(String source) {
  final start = source.indexOf('class SetUnionResult');
  final end = source.indexOf('/// Las columnas de cada tabla', start);
  return {
    for (final m in RegExp(
      r'final int (\w+);',
    ).allMatches(source.substring(start, end)))
      m.group(1)!,
  };
}
