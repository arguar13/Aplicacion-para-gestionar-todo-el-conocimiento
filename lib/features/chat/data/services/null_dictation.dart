import 'package:sinapsis/features/chat/domain/services/dictation.dart';

/// [Dictation] donde no hay reconocedor de voz del sistema al que hablarle
/// (F42): Windows, macOS, Linux, iOS —todavía sin su canal— y la web. El 🎤
/// no aparece.
class NullDictation implements Dictation {
  const NullDictation();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Stream<DictationUpdate> listen({String? localeTag}) =>
      Stream.error(const DictationFailedException('unavailable'));

  @override
  Future<void> stop() async {}
}
