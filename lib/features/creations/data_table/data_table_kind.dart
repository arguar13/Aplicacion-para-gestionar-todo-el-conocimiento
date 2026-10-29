import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/features/creations/data_table/domain/data_table_generator.dart';
import 'package:sinapsis/features/creations/data_table/domain/study_table_json.dart';
import 'package:sinapsis/features/creations/data_table/domain/table_export.dart';
import 'package:sinapsis/features/creations/data_table/presentation/data_table_state.dart';
import 'package:sinapsis/features/creations/data_table/presentation/data_table_viewer.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/domain/services/creation_generator.dart';
import 'package:sinapsis/features/creations/presentation/creation_presentation.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Quien genera las tablas de datos: lo que suma `creationGeneratorsProvider`.
final dataTableGeneratorProvider = Provider<CreationGenerator>(
  (ref) => const DataTableGenerator(),
);

/// La tabla de datos en Repasar (F43, paso 9): la tarjeta y la hoja de
/// fábrica —Idioma, Fuentes y la descripción de qué columnas—, su visor,
/// «Copiar la tabla» y el CSV de «Exportar a CSV» y «Descargar». Lo que suma
/// `creationKindSpecsProvider`.
final dataTableKindSpecProvider = Provider<CreationKindSpec>(
  (ref) => dataTableKindSpec(),
);

/// Lo de [dataTableKindSpecProvider], suelto: lo que usan las pruebas.
CreationKindSpec dataTableKindSpec() =>
    defaultCreationKindSpec(StudyCreationKind.dataTable).copyWith(
      // Unas treinta filas de cinco columnas cortas.
      expectedOutputTokens: (_) => 2200,
      viewerBuilder: (context, creation) =>
          DataTableViewer(key: ValueKey(creation.id), creation: creation),
      viewerActions: dataTableViewerActions,
      exporter: exportDataTable,
    );

/// El CSV de [creation], en el orden que se ve en su visor (si está
/// abierto) y con el separador del idioma de la app (`csvSeparatorFor`);
/// `null` si la tabla no tiene filas.
Future<CreationExportFile?> exportDataTable(
  BuildContext context,
  WidgetRef ref,
  StudyCreation creation,
) async {
  final table = StudyTableJson.decode(creation.decodedContent);
  if (table.isEmpty) return null;
  final l10n = AppLocalizations.of(context)!;
  final locale = Localizations.localeOf(context).toString();
  return CreationExportFile(
    fileName: '${sanitizeFileName(studyCreationTitle(l10n, creation))}.csv',
    bytes: tableToCsv(
      table,
      separator: csvSeparatorFor(locale),
      order: dataTableOrder(ref, creation, table),
    ),
    mimeType: 'text/csv',
  );
}
