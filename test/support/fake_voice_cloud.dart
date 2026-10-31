import 'dart:typed_data';

import 'package:sinapsis/features/narration/domain/voices/mine/voice_cloud.dart';

/// Una ElevenLabs de mentira (F47, paso 4): anota cada pedido y contesta lo
/// que la prueba diga. Nunca sale a internet.
class FakeVoiceCloud implements VoiceCloud {
  FakeVoiceCloud({
    this.accountInfo = const VoiceCloudAccount(
      tier: 'starter',
      creditsUsed: 1000,
      creditLimit: 30000,
      canClone: true,
      voiceSlotsUsed: 1,
      voiceLimit: 10,
    ),
  });

  VoiceCloudAccount accountInfo;

  /// Si se pone, el próximo pedido de ese nombre falla con esto.
  final failures = <String, VoiceCloudException>{};

  final clones = <({String name, String samplePath, String description})>[];
  final designs = <({String description, String text})>[];
  final saved =
      <({String name, String description, String generatedVoiceId})>[];
  final spoken = <({String voiceId, String text})>[];
  final deleted = <String>[];
  int accountChecks = 0;

  var _nextId = 0;

  void _maybeFail(String call) {
    final failure = failures.remove(call);
    if (failure != null) throw failure;
  }

  @override
  Future<VoiceCloudAccount> account() async {
    accountChecks++;
    _maybeFail('account');
    return accountInfo;
  }

  @override
  Future<String> cloneVoice({
    required String name,
    required String samplePath,
    required String description,
  }) async {
    clones.add((name: name, samplePath: samplePath, description: description));
    _maybeFail('cloneVoice');
    return 'clonada-${_nextId++}';
  }

  @override
  Future<List<DesignedVoicePreview>> designPreviews({
    required String description,
    required String text,
  }) async {
    designs.add((description: description, text: text));
    _maybeFail('designPreviews');
    return [
      for (var i = 0; i < 3; i++)
        DesignedVoicePreview(
          generatedVoiceId: 'propuesta-$i',
          audio: Uint8List.fromList([i, i, i]),
          mediaType: 'audio/mpeg',
        ),
    ];
  }

  @override
  Future<String> saveDesignedVoice({
    required String name,
    required String description,
    required String generatedVoiceId,
  }) async {
    saved.add((
      name: name,
      description: description,
      generatedVoiceId: generatedVoiceId,
    ));
    _maybeFail('saveDesignedVoice');
    return 'diseñada-${_nextId++}';
  }

  @override
  Future<Uint8List> speak({
    required String voiceId,
    required String text,
  }) async {
    spoken.add((voiceId: voiceId, text: text));
    _maybeFail('speak');
    return Uint8List.fromList('mp3 de: $text'.codeUnits);
  }

  @override
  Future<void> deleteVoice(String voiceId) async {
    _maybeFail('deleteVoice');
    deleted.add(voiceId);
  }
}
