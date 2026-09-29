import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/core/storage/file_store.dart';
import 'package:sinapsis/core/storage/local_file_store.dart';

void main() {
  late Directory root;
  late LocalFileStore store;

  setUp(() {
    // Un directorio de verdad y no uno simulado: lo que se está probando es
    // justamente dónde terminan los bytes en el disco, y con un sistema de
    // archivos falso se estaría probando el falso.
    root = Directory.systemTemp.createTempSync('sinapsis_store_');
    store = LocalFileStore(rootDirectory: () async => root);
  });

  tearDown(() => root.deleteSync(recursive: true));

  Uint8List bytes(String content) => Uint8List.fromList(content.codeUnits);

  group('nombres de archivo peligrosos', () {
    // El nombre puede venir de otra app, por el botón de compartir. Es
    // entrada no confiable y se trata como tal.

    test('un nombre que sube de directorio no sale de la carpeta', () {
      expect(
        sanitizeFileName('../../databases/sinapsis.db'),
        isNot(contains('/')),
      );
      expect(
        sanitizeFileName('../../databases/sinapsis.db'),
        isNot(contains('..')),
      );
    });

    test('las barras de Windows tampoco pasan', () {
      expect(
        sanitizeFileName(r'..\..\windows\system32\algo.dll'),
        isNot(contains(r'\')),
      );
    });

    test('los dos puntos de unidad de Windows se descartan', () {
      expect(
        sanitizeFileName('C:/Users/ana/secreto.txt'),
        isNot(contains(':')),
      );
    });

    test('los bytes de control y los saltos de línea se descartan', () {
      expect(sanitizeFileName('apunte\n\t\u0000.pdf'), 'apunte___.pdf');
    });

    test('un nombre que queda vacío recibe uno de repuesto', () {
      // Sin esto, el archivo quedaría con un nombre que es solo el
      // identificador y un guion suelto al final.
      expect(sanitizeFileName('///'), 'archivo');
      expect(sanitizeFileName('...'), 'archivo');
      expect(sanitizeFileName('   '), 'archivo');
    });

    test('un nombre que empieza con punto deja de estar oculto', () {
      expect(sanitizeFileName('.perfil'), 'perfil');
    });

    test('un nombre larguísimo se recorta pero conserva la extensión', () {
      // La extensión decide con qué app se abre el archivo. Recortar sin
      // cuidado la perdería.
      final long = '${'a' * 300}.pdf';
      final result = sanitizeFileName(long);

      expect(result.length, lessThanOrEqualTo(120));
      expect(result, endsWith('.pdf'));
    });

    test('un nombre normal no se toca', () {
      expect(
        sanitizeFileName('Apuntes de biologia 2026.pdf'),
        'Apuntes de biologia 2026.pdf',
      );
    });

    test('los acentos y la eñe se conservan', () {
      // Esta app se usa en español. Convertir `biología` en `biolog_a` sería
      // romper algo que no hacía falta romper, y ninguna letra es un
      // separador de rutas.
      expect(
        sanitizeFileName('Biología del año 2026 — apuntes.pdf'),
        'Biología del año 2026 _ apuntes.pdf',
      );
    });

    test('un nombre en otro alfabeto también se conserva', () {
      expect(sanitizeFileName('日本語のメモ.pdf'), '日本語のメモ.pdf');
    });

    test('el recorte cuenta bytes, no caracteres', () {
      // Los sistemas de archivos miden en bytes: el límite habitual de 255 lo
      // alcanzan 255 letras latinas, pero solo 85 ideogramas.
      final result = sanitizeFileName('${'あ' * 200}.pdf');

      expect(utf8.encode(result).length, lessThanOrEqualTo(120));
      expect(result, endsWith('.pdf'));
      // Y el corte va en el borde de un carácter: partir una secuencia UTF-8
      // por la mitad produce un nombre inválido.
      expect(result, contains('あ'));
      expect(() => utf8.decode(utf8.encode(result)), returnsNormally);
    });
  });

  group('guardar por partes (F21)', () {
    test('lo que llega por partes se guarda entero, en su carpeta', () async {
      // Un video de varios GB se guarda así, sin estar entero en memoria.
      final path = await store.saveStream(
        bytes: Stream.fromIterable([bytes('primera '), bytes('segunda')]),
        suggestedName: 'misa.mp4',
        id: 'src-1',
      );

      expect(path, 'originales/src-1/misa.mp4');
      expect(utf8.decode((await store.read(path))!), 'primera segunda');
    });

    test('si el origen se corta a mitad de camino, no queda un archivo a '
        'medias y se avisa', () async {
      final controller = StreamController<List<int>>();
      final saving = store.saveStream(
        bytes: controller.stream,
        suggestedName: 'cortado.mp4',
        id: 'src-2',
      );
      controller
        ..add(bytes('una parte'))
        ..addError(const FileSystemException('se desconectó'));
      await controller.close();

      await expectLater(saving, throwsA(isA<FileSystemException>()));
      expect(await store.exists('originales/src-2/cortado.mp4'), isFalse);
    });
  });

  group('leer una parte, sin traer el archivo entero (F21)', () {
    late String path;

    setUp(() async {
      path = await store.save(
        bytes: bytes('0123456789'),
        suggestedName: 'libro.pdf',
        id: 'src-1',
      );
    });

    test('un tramo del medio', () async {
      expect(await store.readRange(path, start: 3, length: 4), bytes('3456'));
    });

    test('un tramo que se pasa del final devuelve lo que hay', () async {
      expect(await store.readRange(path, start: 8, length: 10), bytes('89'));
    });

    test('cuánto pesa, sin leerlo', () async {
      expect(await store.sizeOf(path), 10);
    });

    test('la ruta en el disco, para abrirlo desde ahí', () async {
      final local = await store.localPathOf(path);

      expect(local, isNotNull);
      expect(File(local!).readAsStringSync(), '0123456789');
    });

    test('si ya no está, todo devuelve null', () async {
      await store.delete(path);

      expect(await store.readRange(path, start: 0, length: 4), isNull);
      expect(await store.sizeOf(path), isNull);
      expect(await store.localPathOf(path), isNull);
    });
  });

  group('guardar y recuperar', () {
    test('lo guardado vuelve igual', () async {
      final path = await store.save(
        bytes: bytes('el contenido del pdf'),
        suggestedName: 'apunte.pdf',
        id: 'src-1',
      );

      expect(await store.read(path), bytes('el contenido del pdf'));
    });

    test('devuelve una ruta relativa, no absoluta', () async {
      // En iOS la carpeta de la app cambia de ruta entre ejecuciones y en
      // cada actualización. Una ruta absoluta guardada hoy apunta mañana a un
      // directorio que ya no existe, y los archivos "desaparecen" sin que
      // nadie haya borrado nada.
      final path = await store.save(
        bytes: bytes('x'),
        suggestedName: 'apunte.pdf',
        id: 'src-1',
      );

      expect(p.isAbsolute(path), isFalse);
      expect(path, isNot(contains(root.path)));
    });

    test('la ruta usa barras hacia adelante en cualquier plataforma', () async {
      // La base de datos puede viajar entre plataformas en una copia de
      // seguridad. Windows entiende las barras hacia adelante; al revés no.
      final path = await store.save(
        bytes: bytes('x'),
        suggestedName: 'apunte.pdf',
        id: 'src-1',
      );

      expect(path, isNot(contains(r'\')));
      expect(path, startsWith('originales/'));
    });

    test('dos archivos con el mismo nombre no se pisan', () async {
      // Pasa todo el tiempo: "documento.pdf" descargado dos veces de dos
      // sitios distintos.
      final primero = await store.save(
        bytes: bytes('el primero'),
        suggestedName: 'documento.pdf',
        id: 'src-1',
      );
      final segundo = await store.save(
        bytes: bytes('el segundo'),
        suggestedName: 'documento.pdf',
        id: 'src-2',
      );

      expect(primero, isNot(segundo));
      expect(await store.read(primero), bytes('el primero'));
      expect(await store.read(segundo), bytes('el segundo'));
    });

    test('un nombre con barras termina dentro de la carpeta igual', () async {
      final path = await store.save(
        bytes: bytes('x'),
        suggestedName: '../../escape.db',
        id: 'src-1',
      );

      final absolute = await store.resolve(path);
      expect(p.isWithin(root.path, absolute), isTrue);
    });
  });

  group('cuando el archivo ya no está', () {
    test('leer algo que no existe devuelve null, no revienta', () async {
      // Alguien pudo vaciar el almacenamiento de la app desde los ajustes del
      // sistema. El elemento sigue existiendo con su texto ya extraído; lo
      // único que se perdió es la copia del original.
      expect(await store.read('originales/no-existe.pdf'), isNull);
    });

    test('borrar algo que no existe no falla', () async {
      await expectLater(store.delete('originales/no-existe.pdf'), completes);
    });
  });

  group('borrar', () {
    test('deja de poder leerse', () async {
      final path = await store.save(
        bytes: bytes('x'),
        suggestedName: 'apunte.pdf',
        id: 'src-1',
      );

      await store.delete(path);

      expect(await store.read(path), isNull);
    });
  });

  group('exists', () {
    test('dice que sí sin necesidad de leer los bytes', () async {
      final path = await store.save(
        bytes: bytes('x'),
        suggestedName: 'apunte.pdf',
        id: 'src-1',
      );

      expect(await store.exists(path), isTrue);
    });

    test('dice que no si nunca se guardó nada ahí', () async {
      expect(await store.exists('originales/no-existe.pdf'), isFalse);
    });

    test('dice que no después de borrar', () async {
      final path = await store.save(
        bytes: bytes('x'),
        suggestedName: 'apunte.pdf',
        id: 'src-1',
      );

      await store.delete(path);

      expect(await store.exists(path), isFalse);
    });
  });
}
