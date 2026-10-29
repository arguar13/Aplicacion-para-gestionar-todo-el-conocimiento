import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:image/image.dart' as img;
import 'package:sinapsis/features/ai_models/data/services/illustration_service.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_account.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/creations/domain/services/structured_writer.dart';

/// Una cuenta de Gemini que dibuja.
final geminiAccount = IllustrationAccount(
  id: 'g',
  provider: IllustrationProvider.gemini,
  label: 'Personal',
  addedAt: DateTime.utc(2026, 10, 28),
);

/// Otra, la del trabajo.
final workAccount = IllustrationAccount(
  id: 'w',
  provider: IllustrationProvider.gemini,
  label: 'Trabajo',
  addedAt: DateTime.utc(2026, 10, 28),
);

/// Una PNG chiquita de verdad, que se puede dibujar.
Uint8List tinyPng([int seed = 0]) {
  final image = img.Image(width: 8, height: 6);
  img.fill(image, color: img.ColorRgb8(40 + seed * 20, 90, 160));
  return img.encodePng(image);
}

/// El JSON de un mazo como lo escribiría la IA: portada, viñetas, cifra,
/// imagen con texto y cierre, con notas y con lo que pide ilustrar.
Map<String, Object?> deckJson({
  String title = 'Éxodo: liberación y alianza',
  String? template,
  bool cover = true,
  int extraBullets = 0,
}) => {
  'title': title,
  'subtitle': 'Del Egipto de los faraones al Sinaí',
  'format': 'presenter',
  'template': ?template,
  'slides': [
    if (cover)
      {
        'layout': 'cover',
        'title': title,
        'kicker': 'Estudio',
        'illustration_prompt': 'El mar abierto al amanecer',
        'speaker_notes': 'Hoy recorremos el Éxodo.',
      },
    {
      'layout': 'bullets',
      'title': 'Por qué importa',
      'bullets': ['Es el relato fundante', 'Une liberación y alianza'],
      'speaker_notes': 'Primero, por qué importa.',
    },
    {
      'layout': 'big_number',
      'value': '40',
      'label': 'años en el desierto',
      'illustration_prompt': 'Un desierto con huellas',
    },
    {
      'layout': 'image_text',
      'title': 'El Sinaí',
      'body': 'La alianza se sella al pie del monte.',
      'illustration_prompt': 'Una montaña con nubes',
      'speaker_notes': 'Acá está el centro del libro.',
    },
    for (var i = 0; i < extraBullets; i++)
      {
        'layout': 'bullets',
        'title': 'Idea $i',
        'bullets': ['Punto $i'],
      },
    {
      'layout': 'closing',
      'title': 'Lo que hay que llevarse',
      'takeaways': ['La libertad tiene un para qué'],
    },
  ],
};

/// Quien escribe de mentira (F43): contesta con [reply] —el JSON que se le
/// dé para cada pedido— por la orquestación de verdad (`runStructuredRequest`):
/// de una vez o por partes, con su corrección.
class FakeDeckWriter implements StructuredWriter {
  FakeDeckWriter({Object? Function(StructuredCall call)? reply})
    : reply = reply ?? ((_) => deckJson());

  Object? Function(StructuredCall call) reply;

  @override
  int contextTokens = 32000;

  final requests = <StructuredRequest<Object?>>[];
  final calls = <StructuredCall>[];

  /// Si está, cada pedido espera a que se complete.
  Completer<void>? hold;

  @override
  Future<T> writeStructured<T>(StructuredRequest<T> request) {
    requests.add(request);
    return runStructuredRequest(request, (call) async {
      calls.add(call);
      final gate = hold;
      if (gate != null) await gate.future;
      final answer = reply(call);
      return answer is String ? answer : jsonEncode(answer);
    });
  }
}

/// Lo que contesta [FakeIllustrations] a un pedido: una imagen o una falla.
typedef IllustrationOutcome = ({Uint8List? bytes, ImageFailure? failure});

IllustrationOutcome drawn([int seed = 0]) =>
    (bytes: tinyPng(seed), failure: null);

IllustrationOutcome failed(ImageFailure failure) =>
    (bytes: null, failure: failure);

/// Las ilustraciones de mentira: nunca llaman a nadie. Contestan en orden lo
/// de [outcomes] (y después, siempre una imagen) y anotan cada pedido.
class FakeIllustrations implements IllustrationService {
  FakeIllustrations({
    List<IllustrationOutcome>? outcomes,
    List<IllustrationAccount>? accounts,
  }) : outcomes = outcomes ?? [],
       _accounts = accounts ?? [geminiAccount, workAccount];

  final List<IllustrationOutcome> outcomes;
  final List<IllustrationAccount> _accounts;

  final requests =
      <
        ({
          String prompt,
          String? styleHint,
          IllustrationAspect aspect,
          IllustrationAccount? account,
        })
      >[];

  /// Si está, cada pedido espera a que se complete (o a que lo cancelen).
  Completer<void>? hold;

  @override
  Future<List<IllustrationAccount>> accounts() async => _accounts;

  @override
  Future<IllustrationAccount?> defaultAccount() async => _accounts.firstOrNull;

  @override
  Future<IllustrationResult> generate({
    required String prompt,
    String? styleHint,
    IllustrationAspect aspect = IllustrationAspect.square,
    IllustrationSize size = IllustrationSize.standard,
    IllustrationAccount? account,
    CancelToken? cancel,
  }) async {
    requests.add((
      prompt: prompt,
      styleHint: styleHint,
      aspect: aspect,
      account: account,
    ));
    final gate = hold;
    if (gate != null) {
      await Future.any([gate.future, ?cancel?.whenCancel]);
      if (cancel?.isCancelled ?? false) {
        throw const ImageGenerationException(ImageFailure.cancelled);
      }
    }
    final outcome = outcomes.isEmpty ? drawn() : outcomes.removeAt(0);
    if (outcome.failure case final failure?) {
      throw ImageGenerationException(failure);
    }
    final target = account ?? _accounts.first;
    return IllustrationResult(
      image: GeneratedImage(
        bytes: outcome.bytes!,
        mimeType: 'image/png',
        model: 'gemini-nano-banana-2.1',
      ),
      accountId: target.id,
      provider: target.provider,
      inputTokens: 10,
      outputTokens: 1120,
      costUsd: 0.034,
      costIsEstimate: false,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}: no lo usa el tipo');
}
