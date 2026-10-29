import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/creations/data_table/domain/study_table.dart';
import 'package:sinapsis/features/creations/data_table/domain/table_sort.dart';
import 'package:sinapsis/features/creations/data_table/domain/table_values.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/features/creations/presentation/kinds/default_creation_kinds.dart';

/// Por qué columna está ordenada la tabla de la creación `id`, mientras su
/// visor está abierto: lo leen el visor, la hoja de ordenar, «Copiar» y
/// «Exportar a CSV» —lo que se copia y se exporta va en el orden que se ve—.
/// Al cerrar el visor vuelve al orden de la IA.
final dataTableSortProvider = StateProvider.autoDispose
    .family<TableSort?, String>((ref, id) => null);

/// El color de la tabla: el de su tipo.
CreationAccent get dataTableAccent =>
    defaultCreationKindSpec(StudyCreationKind.dataTable).accent;

/// Las filas de [table] en el orden de ahora de la creación [creation].
List<int> dataTableOrder(
  WidgetRef ref,
  StudyCreation creation,
  StudyTable table,
) => tableRowOrder(
  table,
  ref.read(dataTableSortProvider(creation.id)),
  TableCollator(creation.languageCode),
);
