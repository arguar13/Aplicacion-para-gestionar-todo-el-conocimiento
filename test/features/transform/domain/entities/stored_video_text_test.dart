import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/core/util/text_script.dart';
import 'package:sinapsis/features/transform/domain/entities/stored_video_text.dart';

/// Lo ya guardado de un video, contra el idioma que se habla (F45, paso 4):
/// qué se ofrece volver a extraer, y con qué idioma.
void main() {
  const title =
      'Las reliquias de San Francisco de Asís que han fascinado al mundo';
  const arabic =
      '[0:00] بقايا القديس فرنسيس الأسيزي التي أذهلت العالم\n'
      '[0:07] في هذا الفيديو نتحدث عن تاريخ هذه الآثار المقدسة';
  const spanish =
      '[0:00] Las reliquias de San Francisco de Asís han fascinado al mundo, '
      'y en este video vamos a ver por qué son tan importantes para los '
      'fieles y cómo se conservan desde hace más de ochocientos años.';

  test('el árabe que guardó una versión anterior, con «ar» como idioma: se '
      'ofrece, y el «ar» se borra al volver a extraer', () {
    final foreign = foreignVideoTextOf(
      const StoredVideoText(
        sourceId: 'v',
        title: title,
        language: 'ar',
        head: arabic,
      ),
    )!;

    expect(foreign.verdict.script, TextScript.arabic);
    expect(foreign.verdict.language, 'ar');
    // Del título solo se sabe que es latín: no qué idioma.
    expect(foreign.spoken, isNull);
    expect(foreign.sourceFits, isFalse);
    expect(languageToReextract(foreign), isNull);
  });

  test('con el idioma bien guardado, se conserva al volver a extraer', () {
    final foreign = foreignVideoTextOf(
      const StoredVideoText(
        sourceId: 'v',
        title: title,
        language: 'es',
        head: arabic,
      ),
    )!;

    expect(foreign.spoken, 'es');
    expect(languageToReextract(foreign), 'es');
  });

  test('en su idioma, nada que ofrecer', () {
    expect(
      foreignVideoTextOf(
        const StoredVideoText(
          sourceId: 'v',
          title: title,
          language: 'es',
          head: spanish,
        ),
      ),
      isNull,
    );
  });

  test('en Procesado: si la fuente ya tiene su texto en su idioma, alcanza '
      'con traerlo; si no, hay que volver a extraer', () {
    StoredVideoText processed(String? sourceHead) => StoredVideoText(
      sourceId: 'v',
      documentId: 'd',
      title: title,
      language: 'es',
      head: arabic,
      sourceHead: sourceHead,
    );

    expect(foreignVideoTextOf(processed(spanish))!.sourceFits, isTrue);
    expect(foreignVideoTextOf(processed(arabic))!.sourceFits, isFalse);
    expect(foreignVideoTextOf(processed('   '))!.sourceFits, isFalse);
  });
}
