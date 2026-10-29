import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sinapsis/features/creations/data/services/system_creation_sharer.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';

/// La hoja de compartir del sistema, de mentira: guarda lo que se le pide.
class _FakeShareSheet {
  final requests = <ShareParams>[];
  Error? failWith;

  Future<ShareResult> share(ShareParams params) async {
    requests.add(params);
    final failure = failWith;
    if (failure != null) throw failure;
    return const ShareResult('elegida', ShareResultStatus.success);
  }
}

void main() {
  late _FakeShareSheet platform;
  late SystemCreationSharer sharer;

  final pdf = CreationExportFile(
    fileName: 'Éxodo · Presentación.pdf',
    bytes: Uint8List.fromList([0x25, 0x50, 0x44, 0x46]),
    mimeType: 'application/pdf',
  );

  setUp(() {
    platform = _FakeShareSheet();
    sharer = SystemCreationSharer(share: platform.share);
  });

  test(
    'le pasa a la hoja el archivo entero, con su nombre de verdad y su tipo',
    () async {
      await sharer(pdf, title: 'Éxodo');

      final params = platform.requests.single;
      final file = params.files!.single;
      expect(await file.readAsBytes(), pdf.bytes);
      expect(file.mimeType, 'application/pdf');
      // `cross_file` ignora el nombre de `fromData` fuera de la web: sin esto
      // el archivo llegaría a la otra app con un nombre inventado.
      expect(params.fileNameOverrides, ['Éxodo · Presentación.pdf']);
    },
  );

  test('el título va a la hoja y al asunto de un correo', () async {
    await sharer(pdf, title: 'Éxodo');

    final params = platform.requests.single;
    expect(params.title, 'Éxodo');
    expect(params.subject, 'Éxodo');
    expect(params.text, isNull);
  });

  test(
    'en la web nunca cae en un correo: el archivo no sale por ahí',
    () async {
      await sharer(pdf, title: 'Éxodo');

      expect(platform.requests.single.mailToFallbackEnabled, isFalse);
      expect(platform.requests.single.downloadFallbackEnabled, isTrue);
    },
  );

  test('la hoja sale de lo que se tocó (iPad y Mac)', () async {
    const origin = Rect.fromLTWH(12, 300, 336, 64);
    await sharer(pdf, title: 'Éxodo', origin: origin);

    expect(platform.requests.single.sharePositionOrigin, origin);
  });

  test(
    'lo que falla en la hoja sube, para que quien la abrió lo diga',
    () async {
      platform.failWith = StateError('sin hoja');

      await expectLater(sharer(pdf, title: 'Éxodo'), throwsStateError);
    },
  );

  group('dónde se ofrece «Compartir»', () {
    test('en Android, iOS, macOS y Windows sí', () {
      for (final platform in [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.windows,
      ]) {
        expect(
          systemShareSupportsFiles(isWeb: false, platform: platform),
          isTrue,
          reason: '$platform',
        );
      }
    });

    test('en Linux no: share_plus no pasa archivos ahí', () {
      expect(
        systemShareSupportsFiles(isWeb: false, platform: TargetPlatform.linux),
        isFalse,
      );
    });

    test('en la web sí, aunque el navegador corra en Linux', () {
      expect(
        systemShareSupportsFiles(isWeb: true, platform: TargetPlatform.linux),
        isTrue,
      );
    });
  });
}
