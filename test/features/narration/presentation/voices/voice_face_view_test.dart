import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/narration/domain/voices/offline_voice_catalog.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_face.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_profile.dart';
import 'package:sinapsis/features/narration/presentation/voices/voice_face_view.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  group('la cara de una voz en pantalla (F47, paso 3)', () {
    test('las iniciales se leen sobre la cara, en claro y en oscuro: al '
        'menos 4,5 a 1 contra los dos tonos', () {
      for (final voice in OfflineVoiceCatalog.voices) {
        final face = VoiceFace.of(voice.id, voice.name);
        for (final dark in [false, true]) {
          final palette = VoiceFacePalette.of(face, dark: dark);
          expect(
            _contrast(palette.ink, palette.start),
            greaterThanOrEqualTo(4.5),
            reason: '${voice.id} ${dark ? 'oscuro' : 'claro'}',
          );
          expect(
            _contrast(palette.ink, palette.end),
            greaterThanOrEqualTo(4.5),
            reason: '${voice.id} ${dark ? 'oscuro' : 'claro'}',
          );
        }
      }
    });

    test('el mismo tono en claro y en oscuro: se reconoce la misma cara', () {
      final face = VoiceFace.of('vits-piper-es_AR-daniela-high#0', 'Daniela');
      final light = VoiceFacePalette.of(face, dark: false);
      final dark = VoiceFacePalette.of(face, dark: true);
      expect(
        HSLColor.fromColor(light.start).hue,
        closeTo(HSLColor.fromColor(dark.start).hue, 2),
      );
    });

    testWidgets('no dice nada al lector de pantalla, y no crece con la letra '
        'grande', (tester) async {
      final semantics = tester.ensureSemantics();
      final voice = offlineVoiceProfiles(OfflineVoiceCatalog.voices).first;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Center(child: VoiceFaceView.of(voice)),
        ),
      );

      expect(tester.getSize(find.byType(VoiceFaceView)), const Size(48, 48));
      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel(RegExp('.+')), findsNothing);
      semantics.dispose();
    });
  });
}
