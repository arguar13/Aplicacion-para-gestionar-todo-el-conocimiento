import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/narration/data/audio/document_audio_store.dart';
import 'package:sinapsis/features/narration/domain/audio/document_audio.dart';
import 'package:sinapsis/features/narration/domain/audio/speech_audio.dart';
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/read_aloud/readable_document.dart';

import '../../../../support/in_memory_file_store.dart';

const _voice = NarrationVoice(name: 'es-ar', locale: 'es-AR');

DocumentAudioPlan _plan(List<String> lines) {
  var at = 0;
  final segments = [
    for (final line in lines)
      () {
        final segment = ReadableSegment(
          sourceKey: 't',
          start: at,
          end: at + line.length,
          spoken: line,
        );
        at += line.length + 1;
        return segment;
      }(),
  ];
  return DocumentAudioPlan.of(
    segments,
    List.filled(segments.length, _voice),
    fallbackLocale: 'es',
  );
}

const _result = SpeechAudioResult(
  path: '/trabajo/doc-x/audio.m4a',
  mimeType: 'audio/mp4',
  duration: Duration(seconds: 4),
  starts: [Duration.zero, Duration(seconds: 2)],
);

/// F47, paso 5: los audios de los documentos en la bóveda, cada uno en su
/// carpeta con su ficha, sin tabla nueva.
void main() {
  late InMemoryFileStore files;
  late DocumentAudioStore store;
  final now = DateTime.utc(2026, 11, 5, 9);

  setUp(() {
    files = InMemoryFileStore();
    store = DocumentAudioStore(files);
  });

  Future<DocumentAudio> save(
    String id,
    DocumentAudioPlan plan, {
    List<int> bytes = const [1, 2, 3],
  }) => store.save(
    documentId: id,
    title: 'Roma',
    plan: plan,
    result: _result,
    bytes: Stream.value(bytes),
    now: now,
  );

  test(
    'guarda el archivo y su ficha en su carpeta, y lo lee de vuelta',
    () async {
      final plan = _plan(['Uno.', 'Dos.']);
      final saved = await save('processed:p1:text', plan);
      final key = documentAudioKeyOf('processed:p1:text');

      expect(
        saved.reference,
        'originales/audio-documentos/$key/audio-${plan.fingerprint.substring(0, 8)}.m4a',
      );
      expect(
        files.paths,
        unorderedEquals([
          saved.reference,
          'originales/audio-documentos/$key/audio.json',
        ]),
      );
      expect(await files.read(saved.reference), [1, 2, 3]);
      expect(saved.starts, _result.starts);
      expect(saved.voices, const [_voice, _voice]);
      expect(saved.createdAt, now);

      final read = (await store.read('processed:p1:text'))!;
      expect(read.fingerprint, plan.fingerprint);
      expect(read.reference, saved.reference);
      expect(read.duration, const Duration(seconds: 4));
      expect(await store.sizeOf(read), 3);
      expect(await store.read('processed:p2:text'), isNull);
    },
  );

  test('uno nuevo reemplaza al de antes: queda solo el nuevo', () async {
    final first = await save('d', _plan(['Uno.', 'Dos.']));
    final second = await save('d', _plan(['Uno.', 'Tres.']), bytes: [9]);

    expect(second.reference, isNot(first.reference));
    expect(files.paths, hasLength(2));
    expect(files.paths, isNot(contains(first.reference)));
    expect((await store.read('d'))!.reference, second.reference);
    expect(await files.read(second.reference), [9]);
  });

  test(
    'sin el archivo, con la ficha rota o de otro documento, no hay audio',
    () async {
      final saved = await save('d', _plan(['Uno.', 'Dos.']));
      final manifest =
          'originales/audio-documentos/${documentAudioKeyOf('d')}/audio.json';

      await files.delete(saved.reference);
      expect(await store.read('d'), isNull);

      await save('d', _plan(['Uno.', 'Dos.']));
      await files.save(
        bytes: utf8.encode('{roto'),
        suggestedName: 'audio.json',
        id: 'audio-documentos/${documentAudioKeyOf('d')}',
      );
      expect(await store.read('d'), isNull);

      // Una ficha que dice ser de otro documento —la clave es un resumen del
      // id— no es la de este.
      final other = (await save('d', _plan(['Uno.', 'Dos.']))).toJson()
        ..['documentId'] = 'e';
      await files.save(
        bytes: utf8.encode(jsonEncode(other)),
        suggestedName: 'audio.json',
        id: 'audio-documentos/${documentAudioKeyOf('d')}',
      );
      expect(await files.read(manifest), isNotNull);
      expect(await store.read('d'), isNull);
    },
  );

  test('borrar se lleva solo el audio de ese documento', () async {
    await save('d', _plan(['Uno.', 'Dos.']));
    final other = await save('e', _plan(['Uno.', 'Dos.']));

    await store.delete('d');

    expect(await store.read('d'), isNull);
    expect((await store.read('e'))!.reference, other.reference);
    expect(files.paths, hasLength(2));
    // Sin audio, borrar no falla.
    await store.delete('nada');
  });

  test('en un almacén sin rutas en el disco —la web—, no hay ruta', () async {
    final saved = await save('d', _plan(['Uno.', 'Dos.']));
    expect(await store.localPathOf(saved), isNull);
  });
}
