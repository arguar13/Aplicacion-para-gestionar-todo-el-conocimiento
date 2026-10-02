import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/database/app_database.dart';
import 'package:sinapsis/core/domain/entities/ai_provenance.dart';
import 'package:sinapsis/core/domain/entities/content_origin.dart';
import 'package:sinapsis/core/domain/entities/item_relation.dart';
import 'package:sinapsis/core/domain/entities/relation_kind.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/ai_organize/presentation/providers/ai_organize_providers.dart';
import 'package:sinapsis/features/library/presentation/widgets/entity_presentation.dart';
import 'package:sinapsis/features/organize/presentation/providers/organize_providers.dart';
import 'package:sinapsis/features/organize/presentation/widgets/relation_edit_sheet.dart';
import 'package:sinapsis/l10n/generated/app_localizations_es.dart';

import '../../../../support/item_rows.dart';
import '../../../../support/library_harness.dart';

/// La hoja que corrige un vínculo (F27): cambiar el tipo, la frase, borrarlo
/// y, si lo hizo la IA, decir que «no era» —con «Deshacer»—. Contra la base
/// real en memoria: lo que importa es lo que queda guardado.
void main() {
  final es = AppLocalizationsEs();
  late LibraryHarness harness;

  setUp(() async {
    harness = await LibraryHarness.create();
    await insertItemRows(harness.database, id: 'a', title: 'El capítulo uno');
    await insertItemRows(harness.database, id: 'b', title: 'El capítulo dos');
  });

  AppDatabase db() => harness.database;

  /// Crea el vínculo a→b y lo devuelve como lo ve el detalle de «a».
  Future<ItemRelation> seedRelation({
    RelationKind kind = RelationKind.relatedTo,
    bool byAi = false,
    String? note,
  }) async {
    AiProvenance? ai;
    if (byAi) {
      final run = await harness.container
          .read(aiRunRepositoryProvider)
          .startRun('a');
      ai = AiProvenance(runId: run.getOrElse((f) => fail('$f')));
    }
    final created = await harness.container
        .read(organizeRepositoryProvider)
        .createRelation(
          fromItemId: 'a',
          toItemId: 'b',
          kind: kind,
          note: note,
          ai: ai,
        );
    expect(created.isRight(), isTrue, reason: '$created');
    final row = await (db().select(
      db().relations,
    )..where((r) => r.kind.equalsValue(kind))).getSingle();
    return ItemRelation(
      relationId: row.id,
      direction: RelationDirection.outgoing,
      kind: row.kind,
      createdAt: row.createdAt,
      otherItemId: 'b',
      otherItemTitle: 'El capítulo dos',
      otherItemSourceKind: SourceKind.webPage,
      note: row.note,
      origin: row.origin,
      aiRunId: row.aiRunId,
    );
  }

  Future<void> openSheet(WidgetTester tester, ItemRelation relation) async {
    await tester.pumpWidget(
      harness.wrap(
        Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () =>
                    showRelationEditSheet(context, relation: relation),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('uno de la IA lleva la marca y ofrece «No era»', (tester) async {
    final relation = await seedRelation(byAi: true, note: 'Hablan de Roma');

    await openSheet(tester, relation);

    expect(find.byTooltip(es.relationMadeByAi), findsOneWidget);
    expect(find.text(es.aiNotRight), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Hablan de Roma'), findsOneWidget);
  });

  testWidgets('uno de la persona no', (tester) async {
    await openSheet(tester, await seedRelation());

    expect(find.byTooltip(es.relationMadeByAi), findsNothing);
    expect(find.text(es.aiNotRight), findsNothing);
  });

  testWidgets('cambiar el tipo y la frase lo guarda, y deja de ser de la IA', (
    tester,
  ) async {
    await openSheet(tester, await seedRelation(byAi: true));

    await tester.tap(find.text(RelationKind.contradicts.shortLabel(es)));
    await tester.pump();
    // La frase de arriba ya dice lo que va a quedar.
    expect(
      find.text(es.relationKindContradicts('El capítulo dos')),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), 'Dicen lo contrario');
    await tester.tap(find.text(es.detailSave));
    await tester.pumpAndSettle();

    expect(find.byType(RelationEditSheet), findsNothing);
    final row = await db().select(db().relations).getSingle();
    expect(row.kind, RelationKind.contradicts);
    expect(row.note, 'Dicen lo contrario');
    expect(row.origin, ContentOrigin.user);
    expect(row.aiRunId, isNull);
  });

  testWidgets('guardar sin cambiar nada no lo adopta', (tester) async {
    await openSheet(tester, await seedRelation(byAi: true));

    await tester.tap(find.text(es.detailSave));
    await tester.pumpAndSettle();

    expect(find.byType(RelationEditSheet), findsNothing);
    expect(
      (await db().select(db().relations).getSingle()).origin,
      ContentOrigin.ai,
    );
  });

  testWidgets('si ya había uno así entre los dos, avisa que quedaron unidos', (
    tester,
  ) async {
    await seedRelation(kind: RelationKind.cites);
    await openSheet(tester, await seedRelation(byAi: true));

    await tester.tap(find.text(RelationKind.cites.shortLabel(es)));
    await tester.tap(find.text(es.detailSave));
    await tester.pumpAndSettle();

    expect(find.text(es.relationEditMerged), findsOneWidget);
    expect(
      (await db().select(db().relations).getSingle()).kind,
      RelationKind.cites,
    );
  });

  testWidgets('«No era» lo borra, avisa, y «Deshacer» lo devuelve', (
    tester,
  ) async {
    await openSheet(tester, await seedRelation(byAi: true));

    await tester.tap(find.text(es.aiNotRight));
    await tester.pumpAndSettle();

    expect(find.text(es.relationRejected), findsOneWidget);
    expect(await db().select(db().relations).get(), isEmpty);
    expect(await db().select(db().aiRejections).get(), hasLength(1));

    await tester.tap(find.text(es.aiRejectionUndo));
    await tester.pumpAndSettle();

    final back = await db().select(db().relations).getSingle();
    expect(back.origin, ContentOrigin.ai);
    expect(await db().select(db().aiRejections).get(), isEmpty);
  });

  testWidgets('«Eliminar» lo borra sin recordar nada', (tester) async {
    await openSheet(tester, await seedRelation(byAi: true));

    await tester.tap(find.text(es.commonDelete));
    await tester.pumpAndSettle();

    expect(await db().select(db().relations).get(), isEmpty);
    expect(await db().select(db().aiRejections).get(), isEmpty);
  });

  testWidgets('una extracción no ofrece cambiar el tipo, pero sí la frase', (
    tester,
  ) async {
    await openSheet(
      tester,
      await seedRelation(kind: RelationKind.extractedFrom),
    );

    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.text(es.relationEditKindFixed), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Un fragmento clave');
    await tester.tap(find.text(es.detailSave));
    await tester.pumpAndSettle();

    expect(
      (await db().select(db().relations).getSingle()).note,
      'Un fragmento clave',
    );
  });
}
