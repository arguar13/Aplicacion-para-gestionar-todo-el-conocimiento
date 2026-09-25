import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/features/notes/presentation/widgets/derived_note_badge.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/library_harness.dart';

/// La insignia visible de una nota generada (F16, D3).
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create();
  });

  Future<String> seedNote() async {
    await harness.capture('Nota\n\ncuerpo distinto');
    final row = await (harness.database.select(
      harness.database.knowledgeEntries,
    )..limit(1)).getSingle();
    return row.id;
  }

  Future<void> pumpBadge(WidgetTester tester, String itemId) async {
    await tester.pumpWidget(
      harness.wrap(Scaffold(body: DerivedNoteBadge(itemId: itemId))),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('una nota que no es un derivado no dibuja nada', (tester) async {
    final id = await seedNote();

    await pumpBadge(tester, id);

    expect(find.text(es.derivedNoteBadgeLabel), findsNothing);
  });

  testWidgets('una nota generada muestra la insignia', (tester) async {
    final id = await seedNote();
    await (harness.database.update(
      harness.database.knowledgeNotes,
    )..where((n) => n.itemId.equals(id))).write(
      KnowledgeNotesCompanion(
        generatedByModel: const Value('gemma-3n'),
        generatedAt: Value(DateTime(2026, 9, 24)),
      ),
    );

    await pumpBadge(tester, id);

    expect(find.text(es.derivedNoteBadgeLabel), findsOneWidget);
  });
}
