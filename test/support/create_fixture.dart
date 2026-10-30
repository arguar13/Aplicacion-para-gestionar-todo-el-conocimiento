import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/knowledge_item.dart';
import 'package:sinapsis/core/domain/entities/processed_section.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/create_hub/domain/create_kind.dart';
import 'package:sinapsis/features/create_hub/presentation/widgets/create_button.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_document.dart';

/// Lo de «Crear» (F45, paso 7b) para las pruebas: armar su objetivo, mostrar
/// su ✨ y elegir una fila.

/// Un documento procesado de [item] con texto, para «Crear»: no hace falta
/// que exista en la base —lo que se crea lee su texto por su id—.
CreateTarget processedTargetOf(
  KnowledgeItem item, {
  ProcessedSourceLink? source = const ProcessedSourceLink(
    itemId: 'fuente',
    title: 'Fuente',
    inTrash: false,
  ),
  Map<ProcessedSection, int> partCounts = const {ProcessedSection.text: 1},
}) => CreateTarget.processed(
  document: ProcessedDocument(
    summary: ProcessedDocumentSummary(
      id: item.id,
      title: item.title,
      sourceKind: SourceKind.document,
      createdAt: item.createdAt,
      updatedAt: item.updatedAt,
      rev: 1,
      partCounts: partCounts,
    ),
    stats: const {},
    inTrash: false,
    source: source,
  ),
  item: item,
);

/// Una pantalla con el ✨ de [target] en la barra y [body] debajo, como el
/// documento.
Widget createScreen(CreateTarget target, {Widget? body}) => Scaffold(
  appBar: AppBar(actions: [CreateButton(target: target)]),
  body: body ?? const SizedBox.expand(),
);

/// Abre «Crear» y elige [kind].
Future<void> tapCreate(WidgetTester tester, CreateKind kind) async {
  await tester.tap(find.byKey(const Key('create-button')));
  await tester.pumpAndSettle();
  // En una pantalla baja, las de abajo quedan fuera: la hoja se desplaza.
  final row = find.byKey(Key('create-${kind.name}'));
  await tester.scrollUntilVisible(
    row,
    200,
    scrollable: find.descendant(
      of: find.byKey(const Key('create-sheet')),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(row);
  await tester.pumpAndSettle();
}
