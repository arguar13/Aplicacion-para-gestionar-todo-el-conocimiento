import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/app/repair_stored_text.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/database/entry_fields.dart';
import 'package:sinapsis/core/database/repairs/utf8_mojibake_repair.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion_kind.dart';
import 'package:sinapsis/core/domain/entities/suggestion_status.dart';
import 'package:sinapsis/core/logging/logger_provider.dart';
import 'package:sinapsis/core/util/util_providers.dart';

import '../../../support/item_rows.dart';
import '../../../support/processed_rows.dart';
import '../../../support/silent_logger.dart';

/// [text] en UTF-8 leído como Latin-1: lo que guardaba la app antes del
/// arreglo de raíz (F43, M7).
String broken(String text) => latin1.decode(utf8.encode(text));

/// Lo que ya quedó guardado con las letras rotas —«DeclaraciÃ³n»—, arreglado
/// una vez: solo lo que tiene la firma y vuelve a ser texto válido, como una
/// edición más, y sin tocar nada más. Contra SQLite real, en memoria.
void main() {
  const title = 'Declaración de los Derechos del Hombre y del Ciudadano';
  final repairedAt = DateTime(2026, 10, 28, 21);

  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), deviceId: 'telefono');
  });

  tearDown(() => db.close());

  Utf8MojibakeRepair repair() =>
      Utf8MojibakeRepair(db, clock: () => repairedAt);

  Future<KnowledgeEntryRow> entry(String id) => (db.select(
    db.knowledgeEntries,
  )..where((e) => e.id.equals(id))).getSingle();

  Future<List<FieldVersionRow>> versions(String id) =>
      (db.select(db.fieldVersions)..where((f) => f.itemId.equals(id))).get();

  Future<void> insertSuggestion(
    String id, {
    required String target,
    required Map<String, Object?> payload,
    SuggestionKind kind = SuggestionKind.metadata,
    SuggestionStatus status = SuggestionStatus.pending,
  }) => db
      .into(db.suggestions)
      .insert(
        SuggestionsCompanion.insert(
          id: id,
          kind: kind,
          targetItemId: target,
          payloadJson: jsonEncode(payload),
          status: Value(status),
          createdAt: DateTime(2026, 10),
        ),
      );

  Future<String> payloadOf(String id) async => (await (db.select(
    db.suggestions,
  )..where((s) => s.id.equals(id))).getSingle()).payloadJson;

  test('el título de la captura vuelve a ser «Declaración», como una edición '
      'versionada', () async {
    await insertItemRows(
      db,
      id: 'pdf',
      title: broken(title),
      kind: SourceKind.document,
    );
    final before = await entry('pdf');

    final report = await repair().run();

    final after = await entry('pdf');
    expect(after.title, title);
    expect(after.rev, before.rev + 1);
    expect(after.updatedAt, repairedAt);
    expect(after.deviceId, 'telefono');
    expect((await versions('pdf')).map((v) => (v.fieldName, v.updatedAt)), [
      (EntryField.title, repairedAt),
    ]);
    expect(report.titles, 1);
    expect(report.total, 1);
  });

  test('el documento procesado, que copió el título de su fuente, y lo que '
      'está en la papelera también', () async {
    await insertItemRows(db, id: 'fuente', title: broken(title));
    await insertProcessedRows(
      db,
      id: 'procesado',
      title: broken(title),
      sourceItemId: 'fuente',
    );
    await insertItemRows(db, id: 'borrado', title: broken('Ñandú'));
    await (db.update(db.knowledgeEntries)..where((e) => e.id.equals('borrado')))
        .write(KnowledgeEntriesCompanion(deletedAt: Value(DateTime(2026))));

    final report = await repair().run();

    expect((await entry('fuente')).title, title);
    expect((await entry('procesado')).title, title);
    final trashed = await entry('borrado');
    expect(trashed.title, 'Ñandú');
    // Sigue en la papelera: solo cambió el título.
    expect(trashed.deletedAt, DateTime(2026));
    expect(report.titles, 3);
  });

  test('el subtítulo y el autor de la fuente, que salen de los mismos '
      'metadatos', () async {
    await insertItemRows(
      db,
      id: 'pdf',
      title: 'Bien escrito',
      subtitle: broken('Asamblea Nacional — París'),
      kind: SourceKind.document,
    );
    await (db.update(db.knowledgeSources)..where((s) => s.itemId.equals('pdf')))
        .write(KnowledgeSourcesCompanion(authorName: Value(broken('Muñoz'))));

    final report = await repair().run();

    final after = await entry('pdf');
    expect(after.title, 'Bien escrito');
    expect(after.subtitle, 'Asamblea Nacional — París');
    final source = await (db.select(
      db.knowledgeSources,
    )..where((s) => s.itemId.equals('pdf'))).getSingle();
    expect(source.authorName, 'Muñoz');
    expect((await versions('pdf')).map((v) => v.fieldName).toSet(), {
      EntryField.subtitle,
      EntryField.authorName,
    });
    expect((report.titles, report.subtitles, report.authors), (0, 1, 1));
  });

  test('no toca lo que no es eso: ni lo bien escrito, ni lo que tiene la '
      'firma pero no vuelve a ser texto válido', () async {
    const fine = ['Declaración', 'Año, señor, pingüino', 'Plain'];
    for (final (i, text) in fine.indexed) {
      await insertItemRows(db, id: 'bien$i', title: text);
    }
    // La última «Ã» abre una letra que no sigue: no es UTF-8.
    await insertItemRows(db, id: 'raro', title: 'DeclaraciÃ³n y Ã');
    final before = {
      for (final id in ['bien0', 'bien1', 'bien2', 'raro']) id: await entry(id),
    };

    final report = await repair().run();

    for (final MapEntry(key: id, value: row) in before.entries) {
      expect(await entry(id), row, reason: id);
      expect(await versions(id), isEmpty, reason: id);
    }
    expect(report.total, 0);
  });

  test('las sugerencias de referencia pendientes se arreglan; las decididas '
      'y las de otro tipo quedan como estaban', () async {
    await insertItemRows(db, id: 'pdf', title: 'Un PDF');
    final payload = {
      'title': broken(title),
      'contributors': [
        {'family': broken('Muñoz'), 'given': 'José'},
      ],
      'volume': 3,
    };
    await insertSuggestion('pendiente', target: 'pdf', payload: payload);
    await insertSuggestion(
      'aceptada',
      target: 'pdf',
      payload: payload,
      status: SuggestionStatus.accepted,
    );
    await insertSuggestion(
      'otra',
      target: 'pdf',
      payload: payload,
      kind: SuggestionKind.property,
    );

    final report = await repair().run();

    expect(jsonDecode(await payloadOf('pendiente')), {
      'title': title,
      'contributors': [
        {'family': 'Muñoz', 'given': 'José'},
      ],
      'volume': 3,
    });
    expect(await payloadOf('aceptada'), jsonEncode(payload));
    expect(await payloadOf('otra'), jsonEncode(payload));
    expect(report.suggestions, 1);
  });

  test('una segunda pasada no encuentra nada ni cambia nada', () async {
    await insertItemRows(db, id: 'pdf', title: broken(title));
    await repair().run();
    final once = await entry('pdf');

    final report = await repair().run();

    expect(report.total, 0);
    expect(await entry('pdf'), once);
  });

  group('una sola vez por instalación, al abrir la bóveda', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    ProviderContainer container() {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sharedPreferencesProvider.overrideWithValue(prefs),
          appLoggerProvider.overrideWithValue(const SilentLogger()),
          clockProvider.overrideWithValue(() => repairedAt),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('arregla y lo anota; la vez siguiente ni mira', () async {
      await insertItemRows(db, id: 'pdf', title: broken(title));

      final first = await repairUtf8MojibakeOnce(container().read);

      expect(first?.titles, 1);
      expect((await entry('pdf')).title, title);
      expect(prefs.getBool(utf8MojibakeRepairDoneKey), isTrue);

      // Algo que llegara roto después —no debería: la raíz ya está
      // arreglada— no se busca más.
      await retitleItemRows(db, 'pdf', broken(title));
      final second = await repairUtf8MojibakeOnce(container().read);

      expect(second, isNull);
      expect((await entry('pdf')).title, broken(title));
    });
  });
}
