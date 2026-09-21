import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/features/vault/data/services/system_vault_backup_file_gateway.dart';
import 'package:sinapsis/features/vault/domain/entities/vault_backup_target.dart';

/// Lo que del selector de la copia se puede probar sin un teléfono (F12): el
/// nombre con que se le muestra al usuario dónde quedó en Android, y el
/// guardado en escritorio, que copia el archivo con `dart:io`. El selector
/// mismo y el
/// Storage Access Framework se prueban en el emulador.
void main() {
  group('describeSafTarget', () {
    test('la carpeta Descargas del almacenamiento principal', () {
      expect(
        describeSafTarget(
          'content://com.android.externalstorage.documents/tree/primary%3ADownload',
          'sinapsis-backup.zip',
        ),
        'primary:Download/sinapsis-backup.zip',
      );
    });

    test('una subcarpeta, con la barra codificada', () {
      expect(
        describeSafTarget(
          'content://com.android.externalstorage.documents/tree/primary%3ADocuments%2FCopias',
          'a.zip',
        ),
        'primary:Documents/Copias/a.zip',
      );
    });

    test('un árbol con un documento adentro se queda con el árbol', () {
      expect(
        describeSafTarget(
          'content://com.android.externalstorage.documents/tree/1234-ABCD%3AMis%20copias/document/1234-ABCD%3AMis%20copias',
          'a.zip',
        ),
        '1234-ABCD:Mis copias/a.zip',
      );
    });

    test('un URI sin árbol se muestra como vino', () {
      expect(
        describeSafTarget('content://raro', 'a.zip'),
        'content://raro/a.zip',
      );
    });

    test('un URI mal codificado no rompe: se muestra tal cual', () {
      expect(
        describeSafTarget('content://x/tree/primary%3', 'a.zip'),
        'primary%3/a.zip',
      );
    });
  });

  group('save, en escritorio', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('sinapsis_gateway_');
    });

    tearDown(() => dir.delete(recursive: true));

    test('copia el archivo a la ruta elegida y devuelve esa ruta', () async {
      final source = File(p.join(dir.path, 'copia.zip'))
        ..writeAsBytesSync(List.generate(300000, (i) => i & 0xff));
      final destination = p.join(dir.path, 'elegido.zip');

      final shown = await const SystemVaultBackupFileGateway().save(
        target: VaultBackupTarget(
          location: destination,
          fileName: 'elegido.zip',
        ),
        sourcePath: source.path,
      );

      expect(shown, destination);
      expect(File(destination).readAsBytesSync(), source.readAsBytesSync());
      // El original queda: quien lo armó lo suelta.
      expect(source.existsSync(), isTrue);
    });

    test('reemplaza lo que ya había: el selector ya lo confirmó', () async {
      final source = File(p.join(dir.path, 'copia.zip'))
        ..writeAsBytesSync([1, 2, 3]);
      final destination = File(p.join(dir.path, 'elegido.zip'))
        ..writeAsBytesSync([9, 9, 9, 9, 9]);

      await const SystemVaultBackupFileGateway().save(
        target: VaultBackupTarget(
          location: destination.path,
          fileName: 'elegido.zip',
        ),
        sourcePath: source.path,
      );

      expect(destination.readAsBytesSync(), [1, 2, 3]);
    });

    test('un destino imposible falla, no se traga el error', () async {
      final source = File(p.join(dir.path, 'copia.zip'))..writeAsBytesSync([1]);

      await expectLater(
        const SystemVaultBackupFileGateway().save(
          target: VaultBackupTarget(
            location: p.join(dir.path, 'no-existe', 'adentro', 'a.zip'),
            fileName: 'a.zip',
          ),
          sourcePath: source.path,
        ),
        throwsA(isA<FileSystemException>()),
      );
    });
  });
}
