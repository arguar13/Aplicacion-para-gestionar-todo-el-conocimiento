import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinapsis/features/chat/data/services/method_channel_dictation.dart';
import 'package:sinapsis/features/chat/data/services/null_dictation.dart';
import 'package:sinapsis/features/chat/domain/services/dictation.dart';

/// El lado de Dart del canal de dictado (F42): con los canales simulados, lo
/// que contesta Kotlin (`DictationChannel`) se traduce bien.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('prueba/dictation');
  const events = EventChannel('prueba/dictation/events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const dictation = MethodChannelDictation(methods: methods, events: events);

  tearDown(() {
    messenger
      ..setMockMethodCallHandler(methods, null)
      ..setMockStreamHandler(events, null);
  });

  void answer(Map<String, Object?> replies) {
    messenger.setMockMethodCallHandler(methods, (call) async {
      final reply = replies[call.method];
      if (reply is PlatformException) throw reply;
      return reply;
    });
  }

  group('si hay reconocimiento de voz', () {
    test('lo que dice el sistema', () async {
      answer({'isAvailable': true});
      expect(await dictation.isAvailable(), isTrue);
      answer({'isAvailable': false});
      expect(await dictation.isAvailable(), isFalse);
    });

    test('sin el canal, o si falla, no hay: el 🎤 no aparece', () async {
      expect(await dictation.isAvailable(), isFalse);
      answer({'isAvailable': PlatformException(code: 'x')});
      expect(await dictation.isAvailable(), isFalse);
    });

    test('donde no hay reconocedor, tampoco', () async {
      expect(await const NullDictation().isAvailable(), isFalse);
    });
  });

  group('escuchar', () {
    test('sin permiso, termina con el error que lleva a los ajustes, sin '
        'abrir el micrófono', () async {
      answer({'requestPermission': false});
      var opened = false;
      messenger.setMockStreamHandler(
        events,
        MockStreamHandler.inline(onListen: (_, _) => opened = true),
      );

      await expectLater(
        dictation.listen(),
        emitsError(isA<DictationPermissionDeniedException>()),
      );
      expect(opened, isFalse);
    });

    test('con permiso, da lo oído y el volumen, en el idioma pedido, y '
        'termina con la frase', () async {
      answer({'requestPermission': true});
      Object? arguments;
      messenger.setMockStreamHandler(
        events,
        MockStreamHandler.inline(
          onListen: (args, sink) {
            arguments = args;
            sink
              ..success({'type': 'level', 'value': 0.4})
              ..success({'type': 'heard', 'text': 'hola', 'final': false})
              ..success({'type': 'algo-nuevo'})
              ..success({'type': 'heard', 'text': 'hola mundo', 'final': true})
              ..endOfStream();
          },
        ),
      );

      final updates = await dictation.listen(localeTag: 'es-AR').toList();

      expect(arguments, {'locale': 'es-AR'});
      expect(updates, hasLength(3));
      expect((updates[0] as DictationLevel).level, 0.4);
      expect((updates[1] as DictationHeard).text, 'hola');
      expect((updates[1] as DictationHeard).isFinal, isFalse);
      expect((updates[2] as DictationHeard).text, 'hola mundo');
      expect((updates[2] as DictationHeard).isFinal, isTrue);
    });

    test('los errores del reconocedor llegan con su nombre', () async {
      answer({'requestPermission': true});
      messenger.setMockStreamHandler(
        events,
        MockStreamHandler.inline(
          onListen: (_, sink) {
            sink
              ..error(code: 'network', message: 'sin red')
              ..endOfStream();
          },
        ),
      );

      await expectLater(
        dictation.listen(),
        emitsError(
          isA<DictationFailedException>().having(
            (e) => e.code,
            'code',
            'network',
          ),
        ),
      );
    });

    test('y si el permiso se quitó a mitad, es el de permiso', () async {
      answer({'requestPermission': true});
      messenger.setMockStreamHandler(
        events,
        MockStreamHandler.inline(
          onListen: (_, sink) => sink.error(code: 'permission'),
        ),
      );

      await expectLater(
        dictation.listen(),
        emitsError(isA<DictationPermissionDeniedException>()),
      );
    });

    test('cortar le pide al sistema que deje de escuchar', () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(methods, (call) async {
        calls.add(call.method);
        return null;
      });
      await dictation.stop();
      expect(calls, ['stop']);
    });
  });

  test('un evento roto se ignora', () {
    expect(dictationUpdateFrom(null), isNull);
    expect(dictationUpdateFrom({'type': 'heard'}), isNull);
    expect(dictationUpdateFrom({'type': 'level', 'value': 'x'}), isNull);
    expect(
      (dictationUpdateFrom({'type': 'level', 'value': 3})! as DictationLevel)
          .level,
      1,
    );
  });
}
