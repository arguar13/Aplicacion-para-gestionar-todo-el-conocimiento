import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/map/domain/usecases/export_map_usecase.dart';

import '../../../../support/fake_file_saver.dart';

/// Guardar el mapa (F14, D7): el archivo entero, con el nombre que se sugiere,
/// y un error del diálogo de guardado no se pierde.
void main() {
  test('guarda los bytes con el nombre pedido', () async {
    final saver = FakeFileSaver();
    final bytes = Uint8List.fromList([1, 2, 3]);

    final result = await ExportMapUseCase(saver: saver)(
      ExportMapParams(fileName: 'mapa-esquema-tema.png', bytes: bytes),
    );

    expect(result.isRight(), isTrue);
    expect(saver.savedFileName, 'mapa-esquema-tema.png');
    expect(saver.savedBytes, bytes);
  });

  test('cancelar el diálogo no es un error', () async {
    final saver = FakeFileSaver(path: null);

    final result = await ExportMapUseCase(saver: saver)(
      ExportMapParams(fileName: 'mapa.svg', bytes: Uint8List(0)),
    );

    expect(result.isRight(), isTrue);
  });

  test('un fallo al guardar vuelve como un fallo de exportación', () async {
    final saver = FakeFileSaver()..error = StateError('disco lleno');

    final result = await ExportMapUseCase(saver: saver)(
      ExportMapParams(fileName: 'mapa.svg', bytes: Uint8List(0)),
    );

    expect(result.isLeft(), isTrue);
    result.fold(
      (failure) => expect(failure.message, contains('disco lleno')),
      (_) => fail('debía fallar'),
    );
  });
}
