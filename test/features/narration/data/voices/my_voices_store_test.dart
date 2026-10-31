import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/features/narration/data/voices/my_voices_store.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/kokoro_blend.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/my_voice.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_traits.dart';

MyVoice _voice(String id, {DateTime? at}) => MyVoice(
  id: id,
  name: 'Voz $id',
  origin: VoiceOrigin.created,
  home: MyVoiceHome.phone,
  locale: 'es',
  createdAt: at ?? DateTime.utc(2026, 10, 31),
  blend: KokoroBlend(
    locale: 'es',
    timbre: const [BlendPart(28, 0.5), BlendPart(3, 0.5)],
    prosody: const [BlendPart(28, 1)],
  ),
  slot: 0,
);

void main() {
  late Directory root;
  late MyVoicesStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('mias-');
    store = MyVoicesStore(rootDirectory: () async => root);
    addTearDown(() async {
      await store.dispose();
      root.deleteSync(recursive: true);
    });
  });

  Directory folder(String id) =>
      Directory(p.join(root.path, 'originales', 'voces-mias', id));

  test('cada voz en su carpeta de la bóveda, con su ficha, de la más vieja a '
      'la más nueva', () async {
    await store.save(_voice('b', at: DateTime.utc(2026, 10, 31, 9)));
    await store.save(_voice('a', at: DateTime.utc(2026, 10, 31, 10)));
    expect(File(p.join(folder('b').path, 'voz.json')).existsSync(), isTrue);
    expect([for (final v in await store.list()) v.id], ['b', 'a']);
    expect(
      Directory(
        p.join(folder('a').path),
      ).listSync().where((e) => e.path.endsWith('.escribiendo')),
      isEmpty,
    );
  });

  test('una ficha ilegible no se muestra, y su carpeta queda', () async {
    await store.save(_voice('a'));
    folder('roto').createSync(recursive: true);
    File(p.join(folder('roto').path, 'voz.json')).writeAsStringSync('{roto');
    folder('otra').createSync();
    File(
      p.join(folder('otra').path, 'voz.json'),
    ).writeAsStringSync('{"id": "distinta"}');
    expect([for (final v in await store.list()) v.id], ['a']);
    expect(folder('roto').existsSync(), isTrue);
  });

  test('guarda la grabación y la muestra en la carpeta de la voz, y borrar '
      'la voz borra todo eso y nada más', () async {
    await store.save(_voice('a'));
    await store.save(_voice('b'));
    final source = File(p.join(root.path, 'grabado.wav'))
      ..writeAsStringSync('audio');
    final kept = await store.keep('a', source, 'grabacion.wav');
    await store.write('a', [1, 2, 3], 'muestra.mp3');
    expect(kept.path, p.join(folder('a').path, 'grabacion.wav'));
    expect((await store.fileOf('a', 'muestra.mp3'))!.lengthSync(), 3);
    expect(await store.fileOf('a', null), isNull);
    expect(await store.fileOf('a', 'no-esta.mp3'), isNull);

    final changes = <void>[];
    final listening = store.changes().listen(changes.add);
    await store.delete('a');
    await Future<void>.delayed(Duration.zero);
    await listening.cancel();
    expect(folder('a').existsSync(), isFalse);
    expect(folder('b').existsSync(), isTrue);
    expect(source.existsSync(), isTrue);
    expect(changes, hasLength(1));
  });

  test('un id o un nombre que salen de su carpeta no se aceptan', () async {
    await expectLater(store.folderOf('../otro'), throwsArgumentError);
    await expectLater(store.folderOf(''), throwsArgumentError);
    await expectLater(store.delete('..'), throwsArgumentError);
    // El nombre de un archivo se reduce a su última parte.
    final file = await store.write('a', [1], '../../afuera.txt');
    expect(p.dirname(file.path), folder('a').path);
  });
}
