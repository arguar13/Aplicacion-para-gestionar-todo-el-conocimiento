import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sinapsis/features/narration/data/voices/my_voices_store.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/kokoro_blend.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/my_voice.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/recording_check.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_traits.dart';

import '../../../../support/test_vault.dart';

final _blend = KokoroBlend(
  locale: 'es',
  timbre: const [BlendPart(28, 0.6), BlendPart(3, 0.4)],
  prosody: const [BlendPart(28, 1)],
);

MyVoice _created(String id, DateTime at, {String? name}) => MyVoice(
  id: id,
  name: name ?? id,
  origin: VoiceOrigin.created,
  home: MyVoiceHome.phone,
  locale: 'es',
  createdAt: at,
  blend: _blend,
);

MyVoice _cloned(String id) => MyVoice(
  id: id,
  name: 'Papá',
  origin: VoiceOrigin.cloned,
  home: MyVoiceHome.elevenLabs,
  locale: 'es-AR',
  createdAt: DateTime.utc(2026, 10, 30),
  cloudVoiceId: 'eleven-$id',
  consent: VoiceConsent(
    kind: VoiceConsentKind.permission,
    personName: 'Jorge',
    grantedAt: DateTime.utc(2026, 10, 30, 12),
  ),
  recording: const MyVoiceRecording(
    file: 'grabacion.wav',
    report: RecordingReport(
      total: Duration(seconds: 90),
      voiced: Duration(seconds: 75),
      noiseDb: -70,
      voiceDb: -18,
      clippedRatio: 0,
    ),
    uploaded: false,
  ),
  sampleFile: 'muestra.mp3',
);

/// Las voces propias en la unión de bóvedas (F47, paso 4): viven en la
/// carpeta de Mías, sin filas, y la unión las trae —ficha, grabación,
/// muestra y consentimiento—, sin pisar nada de acá, sin traer las que se
/// borraron acá y sin dejar nada si la unión falla.
void main() {
  late TestVault tel;
  late TestVault pc;
  late MyVoicesStore telVoices;
  late MyVoicesStore pcVoices;

  setUp(() async {
    tel = await TestVault.create(deviceId: 'tel');
    pc = await TestVault.create(deviceId: 'pc');
    telVoices = MyVoicesStore(rootDirectory: () async => tel.docs);
    pcVoices = MyVoicesStore(rootDirectory: () async => pc.docs);
  });

  tearDown(() async {
    await telVoices.dispose();
    await pcVoices.dispose();
    await tel.dispose();
    await pc.dispose();
  });

  /// Una clonada en [store], con su grabación y su muestra.
  Future<void> saveCloned(MyVoicesStore store, String id) async {
    await store.save(_cloned(id));
    await store.write(id, List.filled(40, 1), 'grabacion.wav');
    await store.write(id, List.filled(10, 2), 'muestra.mp3');
  }

  String voiceFile(String id, String name) =>
      'originales/${MyVoicesStore.folderName}/$id/$name';

  test('la copia de la bóveda lleva la carpeta de Mías', () async {
    await saveCloned(pcVoices, 'v1');
    final names = {
      for (final f in ZipDecoder().decodeBytes(await pc.zip()).files)
        if (f.isFile) f.name,
    };
    expect(
      names,
      containsAll([
        voiceFile('v1', 'voz.json'),
        voiceFile('v1', 'grabacion.wav'),
        voiceFile('v1', 'muestra.mp3'),
      ]),
    );
  });

  test('una voz que llega entra entera —ficha, consentimiento, grabación y '
      'muestra—, y la vista previa la cuenta igual que la unión', () async {
    await saveCloned(pcVoices, 'v1');

    final preview = await tel.previewFrom(pc);
    expect(preview.newMyVoices, 1);
    expect(preview.hasNothingNew, isFalse);

    final result = await tel.mergeFrom(pc);
    expect(result.myVoicesAdded, 1);
    expect(result.filesCopied, preview.newFiles);
    expect(result.filesCopiedBytes, preview.newFilesBytes);
    expect(result.changedNothing, isFalse);

    final voice = (await telVoices.list()).single;
    expect(voice.toJson(), _cloned('v1').toJson());
    expect(voice.consent!.personName, 'Jorge');
    expect(tel.readOriginal(voiceFile('v1', 'grabacion.wav')), hasLength(40));
    expect(tel.hasOriginal(voiceFile('v1', 'muestra.mp3')), isTrue);
  });

  test('unir otra vez no trae nada', () async {
    await saveCloned(pcVoices, 'v1');
    await tel.mergeFrom(pc);
    final again = await tel.mergeFrom(pc);
    expect(again.myVoicesAdded, 0);
    expect(again.changedNothing, isTrue);
    expect((await tel.previewFrom(pc)).hasNothingNew, isTrue);
  });

  test('nunca pisa lo de acá: la ficha cambiada se queda, y solo entra lo '
      'que le falta', () async {
    await saveCloned(pcVoices, 'v1');
    await tel.mergeFrom(pc);
    await telVoices.save(_cloned('v1').copyWith(name: 'Viejo'));
    File(
      p.join(
        tel.docs.path,
        p.joinAll(voiceFile('v1', 'muestra.mp3').split('/')),
      ),
    ).deleteSync();

    final result = await tel.mergeFrom(pc);

    expect(result.myVoicesAdded, 0);
    expect(result.filesCopied, 1);
    expect((await telVoices.list()).single.name, 'Viejo');
    expect(tel.hasOriginal(voiceFile('v1', 'muestra.mp3')), isTrue);
  });

  test('una voz borrada acá no vuelve con una copia hecha antes de '
      'borrarla', () async {
    await saveCloned(pcVoices, 'v1');
    await tel.mergeFrom(pc);
    await telVoices.delete('v1');

    final preview = await tel.previewFrom(pc);
    expect(preview.newMyVoices, 0);
    final result = await tel.mergeFrom(pc);

    expect(result.myVoicesAdded, 0);
    expect(await telVoices.list(), isEmpty);
    expect(tel.hasOriginal(voiceFile('v1', 'voz.json')), isFalse);
  });

  test(
    'lo que se borró allá queda anotado acá, sin borrar nada de acá',
    () async {
      await saveCloned(pcVoices, 'v1');
      await tel.mergeFrom(pc);
      await pcVoices.delete('v1');
      await pcVoices.save(_created('v2', DateTime.utc(2026, 10, 31)));

      await tel.mergeFrom(pc);

      // La de acá sigue: unir no achica.
      expect([
        for (final v in await telVoices.list()) v.id,
      ], containsAll(['v1', 'v2']));
      expect(await telVoices.deletedIds(), {'v1'});
    },
  );

  test('las creadas de las dos bóvedas no chocan: cada una tiene su lugar '
      'en el voices.bin', () async {
    await telVoices.save(_created('a-tel', DateTime.utc(2026, 10)));
    await pcVoices.save(_created('b-pc', DateTime.utc(2026, 9)));

    await tel.mergeFrom(pc);

    final slots = blendSlots(await telVoices.list());
    expect(slots, {'b-pc': 0, 'a-tel': 1});
  });

  test('lo que una escritura cortada dejó a medias no se trae', () async {
    await pcVoices.save(_created('v1', DateTime.utc(2026, 10)));
    File(
      p.join(
        pc.docs.path,
        p.joinAll(voiceFile('v1', 'voz.json.escribiendo').split('/')),
      ),
    ).writeAsStringSync('{a medias');

    await tel.mergeFrom(pc);

    expect(tel.hasOriginal(voiceFile('v1', 'voz.json')), isTrue);
    expect(tel.hasOriginal(voiceFile('v1', 'voz.json.escribiendo')), isFalse);
  });

  test(
    'si la unión falla, no queda ninguna voz ni la lista cambiada',
    () async {
      await saveCloned(pcVoices, 'v1');
      await pcVoices.delete('v1');
      await saveCloned(pcVoices, 'v2');

      await expectLater(
        tel.mergeFrom(
          pc,
          afterFiles: (_) async => throw StateError('roto a propósito'),
        ),
        throwsA(isA<StateError>()),
      );

      expect(await telVoices.list(), isEmpty);
      expect(await telVoices.deletedIds(), isEmpty);
      expect(
        Directory(
          p.join(tel.docs.path, 'originales', MyVoicesStore.folderName, 'v2'),
        ).existsSync(),
        isFalse,
      );
    },
  );
}
