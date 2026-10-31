import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/narration/data/voices/kokoro_style_bank.dart';
import 'package:sinapsis/features/narration/data/voices/my_voices_store.dart';
import 'package:sinapsis/features/narration/data/voices/offline_voice_files.dart';
import 'package:sinapsis/features/narration/domain/entities/narration_voice.dart';
import 'package:sinapsis/features/narration/domain/services/offline_speech_synthesizer.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/kokoro_blend.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/my_voice.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/recording_check.dart';
import 'package:sinapsis/features/narration/domain/voices/mine/voice_cloud.dart';
import 'package:sinapsis/features/narration/domain/voices/offline_voice_catalog.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_samples.dart';
import 'package:sinapsis/features/narration/domain/voices/voice_traits.dart';

/// Clonar, crear, oír y borrar las voces de la pestaña Mías (F47, paso 4).
///
/// - **Creadas en el teléfono** (decisión C, por defecto y gratis): se
///   guardan con su mezcla y su lugar en el `voices.bin` de las creadas
///   ([KokoroStyleBank]), que se arma de nuevo cada vez que cambian y que el
///   motor lee como el de Kokoro.
/// - **En ElevenLabs** (solo si la persona lo eligió): clonadas con su
///   grabación y su consentimiento, o diseñadas desde una descripción; se
///   guarda su id allá y una muestra ya generada.
/// - **Borrar** borra la carpeta de la voz —ficha, grabación, muestra— y, si
///   vive en ElevenLabs, primero allá: si allá no se pudo, acá no se borra,
///   salvo que se pida borrar solo acá.
class MyVoicesService {
  MyVoicesService({
    required MyVoicesStore store,
    required IdGenerator ids,
    required Clock clock,
    OfflineVoiceFiles? files,
    OfflineSpeechSynthesizer? synthesizer,
    VoiceCloud? cloud,
    KokoroStyleBank bank = const KokoroStyleBank(),
  }) : _store = store,
       _ids = ids,
       _clock = clock,
       _files = files,
       _synthesizer = synthesizer,
       _cloud = cloud,
       _bank = bank;

  final MyVoicesStore _store;
  final IdGenerator _ids;
  final Clock _clock;
  final OfflineVoiceFiles? _files;
  final OfflineSpeechSynthesizer? _synthesizer;
  final VoiceCloud? _cloud;
  final KokoroStyleBank _bank;

  /// Las operaciones sobre el `voices.bin` de a una: dos que escriben a la
  /// vez dejarían uno mezclado.
  Future<void> _queue = Future.value();

  Future<T> _serial<T>(Future<T> Function() work) {
    final run = _queue.then((_) => work());
    _queue = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  Stream<void> changes() => _store.changes();

  Future<List<MyVoice>> list() => _store.list();

  /// Si hay con qué crear en el teléfono: el paquete de Kokoro bajado.
  Future<bool> canCreateOnPhone() async =>
      await _files?.kokoroStyles() != null && _synthesizer != null;

  // --- Leer con una voz creada en el teléfono ------

  /// La voz sin conexión de una creada en el teléfono, para el lector; `null`
  /// si [voice] no es una, o ya no está.
  Future<OfflineVoice?> offlineVoiceOf(NarrationVoice voice) async {
    final id = myVoiceIdOf(voice);
    if (id == null) return OfflineVoiceCatalog.byId(voice.name);
    final mine = (await list()).where((v) => v.id == id).firstOrNull;
    final blend = mine?.blend;
    if (mine == null || blend == null || mine.home != MyVoiceHome.phone) {
      return null;
    }
    return OfflineVoice.blend(
      id: mine.id,
      speakerId: mine.slot!,
      name: mine.name,
      locale: blend.locale,
      kokoroPhonemes: blend.phonemes,
      pace: blend.pace,
    );
  }

  /// Los archivos con que el motor lee [voice]: los de su paquete y, si es
  /// una creada, el `voices.bin` de las creadas, armado si hace falta.
  Future<OfflineVoiceEngineConfig?> engineConfigOf(OfflineVoice voice) async {
    final files = _files;
    if (files == null) return null;
    if (!voice.isBlend) return files.engineConfigOf(voice);
    final styles = await _serial(_ensureBank);
    if (styles == null) return null;
    return files.engineConfigOf(voice, blendStyles: styles);
  }

  /// El `voices.bin` de las creadas, al día con sus fichas; `null` sin el
  /// paquete de Kokoro.
  Future<File?> _ensureBank() async {
    final files = _files;
    final source = await files?.kokoroStyles();
    if (files == null || source == null) return null;
    final target = await files.blendStylesFile('creadas');
    final blends = await _phoneBlends();
    final signature = _signatureOf(blends, source);
    final stamp = File('${target.path}.firma');
    if (target.existsSync() &&
        stamp.existsSync() &&
        stamp.readAsStringSync() == signature) {
      return target;
    }
    await _bank.write(source: source.path, target: target.path, blends: blends);
    stamp.writeAsStringSync(signature, flush: true);
    // Un motor armado antes tiene los estilos de antes en la memoria: se
    // suelta, y el próximo pedido lee los nuevos.
    await _synthesizer?.release();
    return target;
  }

  Future<Map<int, KokoroBlend>> _phoneBlends() async => {
    for (final voice in await list())
      if (voice.home == MyVoiceHome.phone && voice.blend != null)
        voice.slot!: voice.blend!,
  };

  static String _signatureOf(Map<int, KokoroBlend> blends, File source) {
    final slots = blends.keys.toList()..sort();
    return [
      'v1',
      source.lengthSync(),
      for (final slot in slots) '$slot=${blends[slot]!.toJson()}',
    ].join('|');
  }

  // --- Crear en el teléfono ------

  /// Dice [text] con [blend] —todavía sin guardar— y deja el audio en
  /// [outputPath]: la muestra que se escucha al crear una voz. Falla con
  /// [MyVoiceException] sin el paquete de Kokoro.
  Future<void> previewOnPhone({
    required KokoroBlend blend,
    required String text,
    required String outputPath,
  }) => _serial(() async {
    final files = _files;
    final synthesizer = _synthesizer;
    final source = await files?.kokoroStyles();
    if (files == null || synthesizer == null || source == null) {
      throw const MyVoiceException(MyVoiceProblem.kokoroMissing);
    }
    final preview = await files.blendStylesFile('muestra');
    await _bank.write(
      source: source.path,
      target: preview.path,
      blends: {0: blend},
    );
    // El motor de la muestra anterior tiene los estilos de antes.
    await synthesizer.release();
    final voice = OfflineVoice.blend(
      id: 'muestra',
      speakerId: 0,
      name: 'muestra',
      locale: blend.locale,
      kokoroPhonemes: blend.phonemes,
      pace: blend.pace,
    );
    final engine = await files.engineConfigOf(voice, blendStyles: preview);
    if (engine == null) {
      throw const MyVoiceException(MyVoiceProblem.kokoroMissing);
    }
    await synthesizer.synthesize(
      engine: engine,
      speakerId: 0,
      text: text,
      speed: blend.pace,
      outputPath: outputPath,
    );
  });

  /// Guarda una voz creada en el teléfono con [blend], en el primer lugar
  /// libre del `voices.bin` de las creadas.
  Future<MyVoice> createOnPhone({
    required String name,
    required KokoroBlend blend,
    required VoiceDesign design,
    String? description,
    int faceSeed = 0,
  }) async {
    final used = {
      for (final voice in await list())
        if (voice.home == MyVoiceHome.phone) ?voice.slot,
    };
    final slot = List.generate(
      kokoroSpeakerSlots,
      (i) => i,
    ).firstWhere((slot) => !used.contains(slot), orElse: () => -1);
    if (slot < 0) throw const MyVoiceException(MyVoiceProblem.noRoom);
    final voice = MyVoice(
      id: _ids.next(),
      name: name.trim(),
      origin: VoiceOrigin.created,
      home: MyVoiceHome.phone,
      locale: blend.locale,
      createdAt: _clock().toUtc(),
      gender: design.gender,
      age: design.age,
      timbre: design.timbre,
      styles: {?design.style},
      description: _clean(description),
      blend: blend,
      slot: slot,
      faceSeed: faceSeed,
    );
    await _store.save(voice);
    return voice;
  }

  // --- La nube ------

  VoiceCloud get _requireCloud {
    final cloud = _cloud;
    if (cloud == null) {
      throw const VoiceCloudException(VoiceCloudFailure.noKey);
    }
    return cloud;
  }

  /// Clona en ElevenLabs la voz de [sample] —con su consentimiento ya
  /// confirmado— y la guarda con su grabación, su consentimiento y una
  /// muestra de cómo suena. Si guardarla acá falla después de clonarla allá,
  /// se borra allá: no queda una voz en ElevenLabs que la app no conoce.
  Future<MyVoice> cloneInCloud({
    required String name,
    required String locale,
    required VoiceConsent consent,
    required File sample,
    required RecordingReport report,
    required bool uploaded,
    VoiceGender? gender,
    int faceSeed = 0,
  }) async {
    final cloud = _requireCloud;
    final cloudVoiceId = await cloud.cloneVoice(
      name: name.trim(),
      samplePath: sample.path,
      description: 'Sinapsis: voz clonada con permiso de su dueño.',
    );
    final id = _ids.next();
    try {
      final extension = p.extension(sample.path).toLowerCase();
      final kept = await _store.keep(
        id,
        sample,
        'grabacion${extension.isEmpty ? '.wav' : extension}',
      );
      final sampleFile = await _sampleOf(id, cloudVoiceId, locale);
      final voice = MyVoice(
        id: id,
        name: name.trim(),
        origin: VoiceOrigin.cloned,
        home: MyVoiceHome.elevenLabs,
        locale: locale,
        createdAt: _clock().toUtc(),
        gender: gender,
        cloudVoiceId: cloudVoiceId,
        consent: consent,
        recording: MyVoiceRecording(
          file: p.basename(kept.path),
          report: report,
          uploaded: uploaded,
        ),
        sampleFile: sampleFile,
        faceSeed: faceSeed,
      );
      await _store.save(voice);
      return voice;
    } on Object {
      await _store.delete(id);
      await cloud.deleteVoice(cloudVoiceId);
      rethrow;
    }
  }

  /// La muestra de una voz de la nube, generada una vez y guardada: oírla
  /// después no gasta. `null` si su idioma no tiene oración de muestra.
  Future<String?> _sampleOf(
    String id,
    String cloudVoiceId,
    String locale,
  ) async {
    final text = voiceSampleText(locale.split('-').first);
    if (text == null) return null;
    final audio = await _requireCloud.speak(voiceId: cloudVoiceId, text: text);
    final file = await _store.write(id, audio, 'muestra.mp3');
    return p.basename(file.path);
  }

  /// Los caracteres que gasta la muestra de una voz de [language].
  static int sampleCharacters(String language) =>
      voiceSampleText(language)?.length ?? 0;

  /// Tres propuestas de ElevenLabs para [description].
  Future<List<DesignedVoicePreview>> designInCloud({
    required String description,
    required String text,
  }) async =>
      // `async`: sin la nube, la falla llega en el futuro, como las demás.
      _requireCloud.designPreviews(description: description, text: text);

  /// Guarda en ElevenLabs la propuesta elegida y la voz acá, con su audio de
  /// muestra.
  Future<MyVoice> saveDesignedInCloud({
    required String name,
    required String description,
    required DesignedVoicePreview preview,
    required VoiceDesign design,
    int faceSeed = 0,
  }) async {
    final cloud = _requireCloud;
    final cloudVoiceId = await cloud.saveDesignedVoice(
      name: name.trim(),
      description: description.trim(),
      generatedVoiceId: preview.generatedVoiceId,
    );
    final id = _ids.next();
    try {
      final sample = await _store.write(
        id,
        preview.audio,
        'muestra.${preview.extension}',
      );
      final voice = MyVoice(
        id: id,
        name: name.trim(),
        origin: VoiceOrigin.created,
        home: MyVoiceHome.elevenLabs,
        locale: design.locale,
        createdAt: _clock().toUtc(),
        gender: design.gender,
        age: design.age,
        timbre: design.timbre,
        styles: {?design.style},
        description: _clean(description),
        cloudVoiceId: cloudVoiceId,
        sampleFile: p.basename(sample.path),
        faceSeed: faceSeed,
      );
      await _store.save(voice);
      return voice;
    } on Object {
      await _store.delete(id);
      await cloud.deleteVoice(cloudVoiceId);
      rethrow;
    }
  }

  // --- Cambiar y borrar ------

  /// Cambia el nombre o la cara de [voice].
  Future<MyVoice> update(MyVoice voice, {String? name, int? faceSeed}) async {
    final changed = voice.copyWith(name: name?.trim(), faceSeed: faceSeed);
    await _store.save(changed);
    return changed;
  }

  /// El archivo de la muestra ya generada de [voice], o `null`.
  Future<File?> sampleFileOf(MyVoice voice) =>
      _store.fileOf(voice.id, voice.sampleFile);

  /// El archivo de la grabación de una clonada, o `null`.
  Future<File?> recordingOf(MyVoice voice) =>
      _store.fileOf(voice.id, voice.recording?.file);

  /// Borra [voice]: en ElevenLabs primero, si vive allá —y si allá falla, acá
  /// no se borra, salvo con [onlyHere]—, y después su carpeta. Una creada en
  /// el teléfono deja libre su lugar: el `voices.bin` de las creadas se arma
  /// de nuevo con el próximo pedido, porque su firma ya no coincide.
  Future<void> delete(MyVoice voice, {bool onlyHere = false}) async {
    final cloudVoiceId = voice.cloudVoiceId;
    if (voice.home == MyVoiceHome.elevenLabs &&
        cloudVoiceId != null &&
        !onlyHere) {
      await _requireCloud.deleteVoice(cloudVoiceId);
    }
    await _store.delete(voice.id);
  }

  static String? _clean(String? text) {
    final trimmed = text?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

/// Lo que impide crear una voz.
enum MyVoiceProblem {
  /// Crear en el teléfono necesita el paquete de Kokoro.
  kokoroMissing,

  /// No queda lugar en el `voices.bin` de las creadas.
  noRoom,
}

class MyVoiceException implements Exception {
  const MyVoiceException(this.problem);

  final MyVoiceProblem problem;

  @override
  String toString() => 'MyVoiceException(${problem.name})';
}
