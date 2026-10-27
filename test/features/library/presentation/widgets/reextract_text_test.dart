import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/domain/entities/source.dart';
import 'package:sinapsis/core/domain/entities/source_kind.dart';
import 'package:sinapsis/features/library/presentation/widgets/reextract_text.dart';

void main() {
  Source source(SourceKind kind, String? language) => Source(
    id: 'src-1',
    kind: kind,
    capturedAt: DateTime(2026, 10, 27),
    language: language,
  );

  group('el idioma con que se abre "Volver a extraer" (F22)', () {
    test('un video de YouTube guardado con subtítulos en árabe vuelve a '
        'abrirse en español: ese idioma no lo eligió nadie', () {
      // El texto ya guardado en árabe se repara volviendo a extraer: si el
      // diálogo se abriera en «ar», se volvería a bajar la misma pista.
      expect(reextractInitialLanguage(source(SourceKind.youtube, 'ar')), 'es');
    });

    test('uno de los idiomas que se ofrecen se respeta', () {
      expect(reextractInitialLanguage(source(SourceKind.youtube, 'en')), 'en');
      expect(reextractInitialLanguage(source(SourceKind.youtube, 'pt')), 'pt');
    });

    test('sin idioma guardado, el de quien usa la app', () {
      expect(reextractInitialLanguage(source(SourceKind.youtube, null)), 'es');
      expect(reextractInitialLanguage(source(SourceKind.audio, null)), 'es');
    });

    test('un audio que alguien dejó en otro idioma lo conserva', () {
      expect(reextractInitialLanguage(source(SourceKind.audio, 'ar')), 'ar');
    });
  });
}
