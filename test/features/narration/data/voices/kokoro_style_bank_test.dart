import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/features/narration/data/voices/kokoro_style_bank.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/kokoro_blend.dart';

const _perSpeaker = kokoroStyleRows * kokoroStyleWidth;

/// Un `voices.bin` de mentira con [speakers] hablantes: cada número dice de
/// quién es, en qué fila y en qué columna (`sid·1000 + fila + columna/1000`),
/// para saber de dónde salió cada número de la mezcla.
File _voicesBin(Directory folder, int speakers) {
  final styles = Float32List(speakers * _perSpeaker);
  for (var sid = 0; sid < speakers; sid++) {
    for (var row = 0; row < kokoroStyleRows; row++) {
      for (var column = 0; column < kokoroStyleWidth; column++) {
        styles[sid * _perSpeaker + row * kokoroStyleWidth + column] =
            sid * 1000 + row + column / 1000;
      }
    }
  }
  return File(p.join(folder.path, 'voices.bin'))
    ..writeAsBytesSync(styles.buffer.asUint8List());
}

Float32List _read(File file) =>
    Float32List.view(Uint8List.fromList(file.readAsBytesSync()).buffer);

double _at(Float32List styles, int sid, int row, int column) =>
    styles[sid * _perSpeaker + row * kokoroStyleWidth + column];

void main() {
  late Directory folder;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('estilos-');
    addTearDown(() => folder.deleteSync(recursive: true));
  });

  test('cuántos hablantes trae un voices.bin, por su tamaño', () {
    expect(KokoroStyleBank.speakersIn(KokoroStyleBank.speakerBytes * 54), 54);
    // El de Kokoro v1.0: 54 hablantes de 510 × 256 números de 4 bytes.
    expect(KokoroStyleBank.speakerBytes * 54, 28200960);
    expect(
      KokoroStyleBank.speakersIn(KokoroStyleBank.speakerBytes + 4),
      isNull,
    );
    expect(KokoroStyleBank.speakersIn(0), isNull);
  });

  test('cada voz creada ocupa su lugar, con el timbre de unas y la forma de '
      'hablar de otras; el resto queda como en el original', () {
    final source = _voicesBin(folder, 3);
    final target = File(p.join(folder.path, 'mezclas', 'creadas.voices.bin'));
    final blend = KokoroBlend(
      locale: 'es',
      timbre: const [BlendPart(0, 0.25), BlendPart(2, 0.75)],
      prosody: const [BlendPart(1, 1)],
    );
    writeStyleBank(source.path, target.path, {
      1: (
        [for (final part in blend.timbre) (part.speakerId, part.weight)],
        [for (final part in blend.prosody) (part.speakerId, part.weight)],
      ),
    });

    expect(target.lengthSync(), source.lengthSync());
    final styles = _read(target);
    for (final row in [0, 7, kokoroStyleRows - 1]) {
      // El timbre —las primeras 128 columnas—: un cuarto del 0 y tres
      // cuartos del 2.
      for (final column in [0, 64, kokoroTimbreWidth - 1]) {
        expect(
          _at(styles, 1, row, column),
          closeTo(
            0.25 * (row + column / 1000) + 0.75 * (2000 + row + column / 1000),
            1e-2,
          ),
        );
      }
      // La forma de hablar —las últimas 128—: entera del 1.
      for (final column in [kokoroTimbreWidth, kokoroStyleWidth - 1]) {
        expect(
          _at(styles, 1, row, column),
          closeTo(1000 + row + column / 1000, 1e-2),
        );
      }
      // Los demás lugares, intactos.
      expect(_at(styles, 0, row, 5), closeTo(row + 0.005, 1e-3));
      expect(_at(styles, 2, row, 200), closeTo(2000 + row + 0.2, 1e-2));
    }
    expect(File('${target.path}.escribiendo').existsSync(), isFalse);
  });

  test('un voices.bin de otro tamaño, un lugar o una voz que no están, '
      'fallan sin escribir nada', () {
    final source = _voicesBin(folder, 2);
    final target = p.join(folder.path, 'creadas.voices.bin');
    final broken = File(p.join(folder.path, 'roto.bin'))
      ..writeAsBytesSync(List.filled(KokoroStyleBank.speakerBytes + 8, 0));
    expect(
      () => writeStyleBank(broken.path, target, const {}),
      throwsA(isA<KokoroStyleBankException>()),
    );
    expect(
      () => writeStyleBank(source.path, target, {
        2: (const [(0, 1.0)], const [(0, 1.0)]),
      }),
      throwsA(isA<KokoroStyleBankException>()),
    );
    expect(
      () => writeStyleBank(source.path, target, {
        0: (const [(5, 1.0)], const [(0, 1.0)]),
      }),
      throwsA(isA<KokoroStyleBankException>()),
    );
    expect(File(target).existsSync(), isFalse);
  });

  test('en un isolate, con la mezcla tal cual', () async {
    final source = _voicesBin(folder, 2);
    final target = p.join(folder.path, 'creadas.voices.bin');
    await const KokoroStyleBank().write(
      source: source.path,
      target: target,
      blends: {
        0: KokoroBlend(
          locale: 'es',
          timbre: const [BlendPart(1, 1)],
          prosody: const [BlendPart(1, 1)],
        ),
      },
    );
    final styles = _read(File(target));
    expect(_at(styles, 0, 3, 3), closeTo(1003.003, 1e-2));
    expect(_at(styles, 1, 3, 3), closeTo(1003.003, 1e-2));
  });
}
