import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/entry_fields.dart';
import 'package:sinapsis/core/database/knowledge_entry_writer.dart';
import 'package:sinapsis/core/domain/entities/suggestion_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion_status.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/utf8_mojibake.dart';

/// Qué arregló una pasada de [Utf8MojibakeRepair].
class Utf8MojibakeRepairReport {
  const Utf8MojibakeRepairReport({
    this.titles = 0,
    this.subtitles = 0,
    this.authors = 0,
    this.suggestions = 0,
  });

  /// Títulos de elementos —fuentes de la Biblioteca y documentos procesados,
  /// que copian el de su fuente—.
  final int titles;
  final int subtitles;

  /// El autor de una fuente, que sale de los mismos metadatos del PDF.
  final int authors;

  /// Sugerencias de datos bibliográficos todavía sin decidir, leídas del PDF
  /// con el mismo error.
  final int suggestions;

  int get total => titles + subtitles + authors + suggestions;
}

/// Arregla lo que ya quedó guardado con las letras rotas —«DeclaraciÃ³n» por
/// «Declaración»— antes del arreglo de raíz (F43, M7): los metadatos del PDF
/// y el nombre que ofrece una descarga se leían como Latin-1 siendo UTF-8.
///
/// Toca SOLO el texto que salió de ahí —el título y el subtítulo de cada
/// elemento, el autor de cada fuente y las sugerencias de referencia
/// pendientes— y, de ese texto, solo el que tiene la firma exacta del error y
/// vuelve a ser texto válido al leerlo bien ([repairUtf8Mojibake]). Lo demás
/// no se mira. Nada se borra: un título se reemplaza por el mismo título bien
/// escrito.
///
/// Los elementos se escriben con [KnowledgeEntryWriter], como cualquier
/// edición: sube el `rev`, firma el dispositivo y versiona el campo. Así una
/// unión de bóvedas ve el arreglo como lo que es —el cambio más nuevo— y no
/// vuelve a traer el título roto de una copia de antes.
///
/// Se puede correr las veces que se quiera: lo ya arreglado no tiene la
/// firma, y una segunda pasada no encuentra nada. Cada valor se vuelve a leer
/// dentro de su transacción antes de escribirlo: si algo lo cambió entre la
/// búsqueda y el arreglo, se arregla lo que hay ahora —o nada—.
class Utf8MojibakeRepair {
  Utf8MojibakeRepair(this._db, {Clock clock = DateTime.now}) : _clock = clock;

  final AppDatabase _db;
  final Clock _clock;

  Future<Utf8MojibakeRepairReport> run() async {
    final writer = KnowledgeEntryWriter(_db, clock: _clock);
    var titles = 0;
    var subtitles = 0;
    var authors = 0;
    var suggestions = 0;

    // También lo que está en la papelera: puede volver.
    final entries = await _db
        .customSelect('SELECT id, title, subtitle FROM item')
        .get();
    for (final row in entries) {
      final id = row.read<String>('id');
      if (hasUtf8MojibakeSignature(row.read<String>('title'))) {
        final fixed = await _db.transaction(() async {
          final now = await _entryText(id, 'title');
          final fixed = now == null ? null : repairUtf8Mojibake(now);
          if (fixed == null) return false;
          return writer.setFieldFromText(id, EntryField.title, fixed);
        });
        if (fixed) titles++;
      }
      final subtitle = row.readNullable<String>('subtitle');
      if (subtitle != null && hasUtf8MojibakeSignature(subtitle)) {
        final fixed = await _db.transaction(() async {
          final now = await _entryText(id, 'subtitle');
          final fixed = now == null ? null : repairUtf8Mojibake(now);
          if (fixed == null) return false;
          return writer.setFreeText(id, subtitle: Value(fixed));
        });
        if (fixed) subtitles++;
      }
    }

    final sources = await _db
        .customSelect(
          'SELECT item_id, author_name FROM source '
          'WHERE author_name IS NOT NULL',
        )
        .get();
    for (final row in sources) {
      if (!hasUtf8MojibakeSignature(row.read<String>('author_name'))) continue;
      final id = row.read<String>('item_id');
      final fixed = await _db.transaction(() async {
        final now = await _db
            .customSelect(
              'SELECT author_name FROM source WHERE item_id = ?',
              variables: [Variable.withString(id)],
            )
            .getSingleOrNull();
        final author = now?.readNullable<String>('author_name');
        final fixed = author == null ? null : repairUtf8Mojibake(author);
        if (fixed == null) return false;
        return writer.setFieldFromText(id, EntryField.authorName, fixed);
      });
      if (fixed) authors++;
    }

    // Las sugerencias no tienen linaje: se reescribe su `payload_json`, con
    // cada texto arreglado y todo lo demás igual.
    final pending =
        await (_db.select(_db.suggestions)..where(
              (s) =>
                  s.kind.equalsValue(SuggestionKind.metadata) &
                  s.status.equalsValue(SuggestionStatus.pending),
            ))
            .get();
    for (final suggestion in pending) {
      if (!hasUtf8MojibakeSignature(suggestion.payloadJson)) continue;
      final Object? payload;
      try {
        payload = jsonDecode(suggestion.payloadJson);
      } on FormatException {
        continue;
      }
      var changed = false;
      final fixed = _repairJson(payload, () => changed = true);
      if (!changed) continue;
      final written =
          await (_db.update(_db.suggestions)..where(
                (s) =>
                    s.id.equals(suggestion.id) &
                    s.payloadJson.equals(suggestion.payloadJson),
              ))
              .write(
                SuggestionsCompanion(payloadJson: Value(jsonEncode(fixed))),
              );
      if (written > 0) suggestions++;
    }

    return Utf8MojibakeRepairReport(
      titles: titles,
      subtitles: subtitles,
      authors: authors,
      suggestions: suggestions,
    );
  }

  Future<String?> _entryText(String id, String column) async {
    final row = await _db
        .customSelect(
          'SELECT $column FROM item WHERE id = ?',
          variables: [Variable.withString(id)],
        )
        .getSingleOrNull();
    return row?.readNullable<String>(column);
  }
}

/// [value] —lo que sale de `jsonDecode`— con cada texto arreglado; llama a
/// [onFix] por cada uno que cambió.
Object? _repairJson(Object? value, void Function() onFix) => switch (value) {
  final String text => _repairText(text, onFix),
  final List<Object?> list => [
    for (final item in list) _repairJson(item, onFix),
  ],
  final Map<String, Object?> map => {
    for (final MapEntry(:key, :value) in map.entries)
      key: _repairJson(value, onFix),
  },
  _ => value,
};

String _repairText(String text, void Function() onFix) {
  final fixed = repairUtf8Mojibake(text);
  if (fixed == null) return text;
  onFix();
  return fixed;
}
