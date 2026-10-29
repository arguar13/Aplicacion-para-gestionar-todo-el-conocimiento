import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sinapsis/features/creations/data/services/creation_illustration_store.dart';

import '../../../../support/in_memory_file_store.dart';

/// El almacén de las ilustraciones con IA de «Lo creado» (F43, decisión H),
/// el de todos los tipos: lo que borra, cómo las guarda y el barrido de lo
/// que el contenido ya no nombra.
void main() {
  late InMemoryFileStore files;
  late CreationIllustrationStore store;

  setUp(() {
    files = InMemoryFileStore();
    store = CreationIllustrationStore(files);
  });

  Uint8List png([int seed = 0]) => img.encodePng(
    img.Image(width: 4, height: 3)
      ..clear(img.ColorRgb8(10 + seed * 20 % 200, 120, 200)),
  );

  Future<String> save(String creationId, String slotId) => store.save(
    creationId: creationId,
    slotId: slotId,
    bytes: png(),
    mimeType: 'image/png',
  );

  group('borrar', () {
    test('solo lo de la carpeta de la propia creación', () async {
      final path = await save('c1', 'header');
      final original = await files.save(
        bytes: png(),
        suggestedName: 'libro.pdf',
        id: 'documento',
      );
      final another = await save('c10', 'header');

      await store.delete('otra', path);
      await store.delete('c1', original);
      await store.delete('c1', another);
      await store.delete('c1', 'originales/c1/ilustraciones/../../x.pdf');
      expect(files.deleted, isEmpty);

      await store.delete('c1', path);
      expect(files.deleted, [path]);
      expect(files.paths, unorderedEquals([original, another]));
    });

    test(
      'lo de una vuelta cancelada, sin fallar si el disco se resiste',
      () async {
        final a = await save('c1', 'a');
        final b = await save('c1', 'b');
        files.deleteError = StateError('disco');
        await store.deleteQuietly('c1', [a, b]);
        expect(files.paths, hasLength(2));
        files.deleteError = null;
        await store.deleteQuietly('c1', [a, b, 'originales/doc/libro.pdf']);
        expect(files.deleted, [a, b]);
      },
    );
  });

  group('cómo se guardan', () {
    Uint8List noise(int side, {bool transparent = false}) {
      final image = img.Image(
        width: side,
        height: side,
        numChannels: transparent ? 4 : 3,
      );
      final random = math.Random(7);
      for (final pixel in image) {
        pixel
          ..r = random.nextInt(256)
          ..g = random.nextInt(256)
          ..b = random.nextInt(256);
        if (transparent) pixel.a = random.nextInt(256);
      }
      return img.encodePng(image);
    }

    test('una PNG grande, como JPEG; una chica, tal cual', () async {
      final big = noise(640);
      expect(
        big.length,
        greaterThan(CreationIllustrationStore.recompressAbove),
      );

      final saved = await store.save(
        creationId: 'c1',
        slotId: 'diapositiva-3',
        bytes: big,
        mimeType: 'image/png',
      );
      expect(saved, 'originales/c1/ilustraciones/diapositiva-3.jpg');
      final bytes = (await files.read(saved))!;
      expect(bytes.sublist(0, 2), [0xFF, 0xD8]);
      expect(bytes.length, lessThan(big.length));

      expect(await save('c1', 'header'), endsWith('header.png'));
    });

    test('una con transparencias nunca pasa a JPEG: las pondría negras', () {
      final big = noise(640, transparent: true);
      expect(
        big.length,
        greaterThan(CreationIllustrationStore.recompressAbove),
      );
      final kept = fitCreationIllustrationSync(big, 'image/png');
      expect(kept.mimeType, 'image/png');
      expect(kept.bytes, same(big));

      final shrunk = fitCreationIllustrationSync(big, 'image/png', maxSide: 64);
      expect(shrunk.mimeType, 'image/png');
      expect(img.decodeImage(shrunk.bytes)!.width, 64);
    });

    test('con un lado mayor, achicada a él como JPEG; una que no se puede '
        'leer, tal cual', () {
      final wide = img.encodePng(img.Image(width: 1600, height: 1200));
      final shrunk = fitCreationIllustrationSync(
        wide,
        'image/png',
        maxSide: 640,
      );
      expect(shrunk.mimeType, 'image/jpeg');
      final decoded = img.decodeImage(shrunk.bytes)!;
      expect(decoded.width, 640);
      expect(decoded.height, 480);

      final tall = img.encodePng(img.Image(width: 300, height: 1280));
      expect(
        img
            .decodeImage(
              fitCreationIllustrationSync(
                tall,
                'image/png',
                maxSide: 640,
              ).bytes,
            )!
            .height,
        640,
      );

      final junk = Uint8List.fromList([1, 2, 3]);
      final kept = fitCreationIllustrationSync(
        junk,
        'image/webp',
        maxSide: 640,
      );
      expect(kept.bytes, junk);
      expect(kept.mimeType, 'image/webp');
    });
  });

  group('barrer lo que el contenido ya no nombra', () {
    test(
      'se lleva lo suyo sin nombrar y deja lo nombrado y lo de las demás',
      () async {
        final kept = await save('c1', 'a');
        final unused = await save('c1', 'b');
        final loose = await files.save(
          bytes: png(),
          suggestedName: 'suelto.png',
          id: 'c1',
        );
        final another = await save('c10', 'a');

        // Lo que el contenido nombra la primera vez: las dos.
        await store.sweep('c1', named: () async => {kept, unused});
        expect(files.deleted, isEmpty);

        await store.sweep('c1', named: () async => {kept});
        expect(files.deleted, [unused]);
        // Fuera de «ilustraciones» no se barre: lo de la carpeta que no es una
        // ilustración se va con la creación.
        expect(files.paths, unorderedEquals([kept, loose, another]));
      },
    );

    test('si la creación ya no está, no se barre nada', () async {
      final path = await save('c1', 'a');
      await store.sweep('c1', named: () async => {path});
      await store.sweep('c1', named: () async => null);
      expect(files.deleted, isEmpty);
    });

    test('lo guardado que el contenido todavía no nombró no se toca, hasta '
        'que un contenido lo nombra y otro ya no', () async {
      final before = await save('c1', 'a');
      await store.sweep('c1', named: () async => {before});

      // Un ilustrador guardó la nueva; su contenido todavía no se guardó, y
      // otro guardado de la misma creación barre.
      final drawn = await save('c1', 'a');
      await store.sweep('c1', named: () async => {before});
      expect(files.paths, contains(drawn));
      expect(files.deleted, isEmpty);

      // Llega su contenido: la vieja se va.
      await store.sweep('c1', named: () async => {drawn});
      expect(files.deleted, [before]);

      // Y cuando un contenido ya no la nombra, se va también.
      await store.sweep('c1', named: () async => {});
      expect(files.deleted, [before, drawn]);
    });

    test('mientras se guarda una, el barrido espera a que termine y no la '
        'borra, aunque su archivo ya esté en el disco', () async {
      final old = await save('c1', 'a');
      await store.sweep('c1', named: () async => {old});

      final gate = Completer<void>();
      files.saveGate = gate.future;
      final saving = save('c1', 'b');
      await pumpEventQueue();
      final written = files.paths.firstWhere((p) => p.endsWith('b.png'));

      var swept = false;
      final sweeping = store
          .sweep('c1', named: () async => {})
          .then((_) => swept = true);
      await pumpEventQueue();
      expect(swept, isFalse);
      expect(files.deleted, isEmpty);

      files.saveGate = null;
      gate.complete();
      expect(await saving, written);
      await sweeping;
      expect(files.deleted, [old]);
      expect(files.paths, [written]);
    });

    test('lo comparten dos almacenes sobre el mismo disco: el del ilustrador '
        'y el del repositorio', () async {
      final drawn = await save('c1', 'a');
      await CreationIllustrationStore(files).sweep('c1', named: () async => {});
      expect(files.paths, [drawn]);
    });
  });
}
