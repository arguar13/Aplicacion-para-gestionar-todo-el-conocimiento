import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/error/failures.dart';
import 'package:sinapsis/features/atlas/domain/usecases/export_atlas_usecase.dart';

import '../../../../support/fake_file_saver.dart';

/// Guardar el Atlas como Markdown (F13).
void main() {
  const params = ExportAtlasParams(
    fileName: 'atlas-tema.md',
    markdown: '# Atlas — Tema\n\n- **Época** — Madura\n',
  );

  test('guarda el documento en UTF-8 con el nombre que se sugiere', () async {
    final saver = FakeFileSaver();

    final result = await ExportAtlasUseCase(saver: saver)(params);

    expect(result.isRight(), isTrue);
    expect(saver.savedFileName, 'atlas-tema.md');
    expect(utf8.decode(saver.savedBytes!), params.markdown);
  });

  test('cancelar el diálogo de guardado no es un error', () async {
    final saver = FakeFileSaver(path: null);

    final result = await ExportAtlasUseCase(saver: saver)(params);

    expect(result.isRight(), isTrue);
  });

  test(
    'si el guardado falla, es un fallo de exportación con el motivo',
    () async {
      final saver = FakeFileSaver()..error = Exception('sin espacio');

      final result = await ExportAtlasUseCase(saver: saver)(params);

      final failure = result.getLeft().toNullable();
      expect(failure, isA<Failure>());
      expect(failure.toString(), contains('sin espacio'));
    },
  );
}
