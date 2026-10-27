import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';

ReadableSegment _segment(String spoken, {int start = 0}) => ReadableSegment(
  sourceKey: 'k',
  start: start,
  end: start + spoken.length,
  spoken: spoken,
);

void main() {
  final whole = [_segment('Todo el texto.')];
  final summary = [_segment('Un resumen.', start: 20)];

  ReadableDocument document({
    List<ReadableSegment>? segments,
    Map<ReadScope, List<ReadableSegment>>? scopes,
  }) => ReadableDocument(
    id: 'd',
    title: 'D',
    segments: segments ?? whole,
    scopes: scopes ?? {ReadScope.summary: summary},
  );

  group('qué parte se lee (F39)', () {
    test('todo es el texto; cada capa, lo suyo; lo que no se ofrece, nada', () {
      final d = document();

      expect(d.segmentsOf(ReadScope.all), whole);
      expect(d.segmentsOf(ReadScope.summary), summary);
      expect(d.segmentsOf(ReadScope.synthesis), isEmpty);
      expect(d.segmentsOf(ReadScope.keywords), isEmpty);
    });

    test('ofrece solo las partes que tienen algo', () {
      final d = document(
        scopes: {ReadScope.summary: summary, ReadScope.synthesis: []},
      );

      expect(d.offers(ReadScope.all), isTrue);
      expect(d.offers(ReadScope.summary), isTrue);
      expect(d.offers(ReadScope.synthesis), isFalse);
      expect(d.offers(ReadScope.keywords), isFalse);
    });

    test('ofrece elegir la parte si lleva capas, aunque estén vacías: el '
        'reproductor las muestra apagadas', () {
      expect(document(scopes: {ReadScope.summary: []}).hasScopes, isTrue);
      expect(document(scopes: const {}).hasScopes, isFalse);
    });

    test('empieza por todo; sin texto, por la primera capa con algo', () {
      expect(document().defaultScope, ReadScope.all);
      expect(
        document(
          segments: [],
          scopes: {
            ReadScope.summary: [],
            ReadScope.synthesis: summary,
            ReadScope.keywords: summary,
          },
        ).defaultScope,
        ReadScope.synthesis,
      );
    });

    test('está vacío solo si ninguna parte tiene algo', () {
      expect(document(segments: [], scopes: const {}).isEmpty, isTrue);
      expect(
        document(segments: [], scopes: {ReadScope.keywords: []}).isEmpty,
        isTrue,
      );
      expect(document(segments: []).isEmpty, isFalse);
      expect(document(scopes: const {}).isEmpty, isFalse);
    });

    test('con otras capas conserva el texto y si suena en su propio audio', () {
      final other = {ReadScope.keywords: summary};

      final changed = document().withScopes(other);
      expect(changed.segments, whole);
      expect(changed.scopes, other);
      expect(changed.title, document().title);
      expect(changed.ownAudio, isFalse);

      expect(document().withOwnAudio().withScopes(other).ownAudio, isTrue);
    });
  });

  group('un texto con su propio audio (F23, F40)', () {
    test('con lo estudiado, «Todo» se ofrece y se puede elegir', () {
      final d = document().withOwnAudio();

      expect(d.ownAudio, isTrue);
      expect(d.id, document().id);
      expect(d.offers(ReadScope.all), isTrue);
      expect(d.segmentsOf(ReadScope.all), whole);
      expect(d.segmentsOf(ReadScope.summary), summary);
    });

    test('quien no eligió empieza por lo estudiado, no por el texto', () {
      expect(document().withOwnAudio().defaultScope, ReadScope.summary);
      expect(document().defaultScope, ReadScope.all);
    });

    test('sin nada estudiado no ofrece el texto: sería un segundo audio de '
        'lo mismo', () {
      for (final scopes in <Map<ReadScope, List<ReadableSegment>>>[
        const {},
        {ReadScope.summary: <ReadableSegment>[], ReadScope.keywords: []},
      ]) {
        final d = document(scopes: scopes).withOwnAudio();

        expect(d.offers(ReadScope.all), isFalse, reason: '$scopes');
        expect(d.isEmpty, isTrue, reason: '$scopes');
        expect(
          document(scopes: scopes).offers(ReadScope.all),
          isTrue,
          reason: '$scopes',
        );
      }
    });

    test('es parte de la igualdad', () {
      expect(document().withOwnAudio(), isNot(document()));
      expect(document().withOwnAudio(), document().withOwnAudio());
      expect(
        document().withOwnAudio().hashCode,
        document().withOwnAudio().hashCode,
      );
    });

    test('dos documentos son iguales si traen lo mismo, capas incluidas', () {
      expect(document(), document());
      expect(document().hashCode, document().hashCode);
      expect(
        document(),
        isNot(
          document(
            scopes: {
              ReadScope.summary: [_segment('Otro.')],
            },
          ),
        ),
      );
      expect(document(), isNot(document(scopes: const {})));
      // Una capa de más, vacía, en un lado o en el otro.
      final extra = <ReadScope, List<ReadableSegment>>{
        ReadScope.summary: summary,
        ReadScope.synthesis: [],
      };
      expect(document(), isNot(document(scopes: extra)));
      expect(document(scopes: extra), isNot(document()));
      expect(
        document(),
        isNot(document(scopes: {ReadScope.synthesis: summary})),
      );
    });
  });
}
