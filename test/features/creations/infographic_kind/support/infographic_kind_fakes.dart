import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart' show CancelToken;
import 'package:sinapsis/features/ai_models/data/services/illustration_service.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_account.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_capability.dart';
import 'package:sinapsis/features/ai_models/domain/entities/image_generation.dart';
import 'package:sinapsis/features/creations/domain/services/structured_writer.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic.dart';
import 'package:sinapsis/features/creations/infographic/domain/infographic_json.dart';

import '../../infographic/support/sample_infographics.dart';

/// Un PNG de 1×1 de verdad: lo que «dibuja» el servicio de mentira, y que la
/// lámina puede mostrar.
final Uint8List onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGA'
  'WjR9awAAAABJRU5ErkJggg==',
);

/// La cuenta de Gemini «Personal» de las pruebas: la misma que escribe.
final geminiAccount = IllustrationAccount(
  id: 'g',
  provider: IllustrationProvider.gemini,
  label: 'Personal',
  addedAt: DateTime.utc(2026, 10, 28),
);

/// Otra cuenta, la «Trabajo».
final workAccount = IllustrationAccount(
  id: 'w',
  provider: IllustrationProvider.openAi,
  label: 'Trabajo',
  addedAt: DateTime.utc(2026, 10, 28),
);

/// Un pedido que recibió el servicio de mentira.
typedef IllustrationCall = ({
  String prompt,
  String? styleHint,
  IllustrationAspect aspect,
  IllustrationAccount? account,
  CancelToken? cancel,
});

/// El servicio de ilustraciones de mentira: no le pide nada a nadie.
///
/// Cada pedido contesta lo que diga [script] en su lugar —un `ImageFailure`
/// lo hace fallar con eso, un `Error` lo lanza tal cual, un `Completer` lo
/// deja esperando hasta que se complete—; lo que no está en [script], una
/// imagen.
class FakeIllustrationService implements IllustrationService {
  FakeIllustrationService({
    List<IllustrationAccount>? accounts,
    this.capability = const ImageCapability.untested(),
  }) : accountList = accounts ?? [geminiAccount];

  final List<IllustrationAccount> accountList;
  ImageCapability capability;
  final script = <Object?>[];
  final calls = <IllustrationCall>[];

  @override
  Future<List<IllustrationAccount>> accounts() async => accountList;

  @override
  Future<ImageCapability> capabilityOf(IllustrationAccount account) async =>
      capability;

  @override
  Future<IllustrationResult> generate({
    required String prompt,
    String? styleHint,
    IllustrationAspect aspect = IllustrationAspect.square,
    IllustrationSize size = IllustrationSize.standard,
    IllustrationAccount? account,
    CancelToken? cancel,
  }) async {
    final index = calls.length;
    calls.add((
      prompt: prompt,
      styleHint: styleHint,
      aspect: aspect,
      account: account,
      cancel: cancel,
    ));
    final step = index < script.length ? script[index] : null;
    if (step is Completer<void>) await step.future;
    if (step is ImageFailure) throw ImageGenerationException(step);
    if (step is Error) throw step;
    return IllustrationResult(
      image: GeneratedImage(
        bytes: onePixelPng,
        mimeType: 'image/png',
        model: 'gemini-nano-banana-2.1',
      ),
      accountId: account!.id,
      provider: account.provider,
      inputTokens: 12,
      outputTokens: 1120,
      costUsd: 0.034,
      costIsEstimate: false,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'El servicio de mentira no hace ${invocation.memberName}.',
  );
}

/// Quien escribe, de mentira: corre el pedido de verdad
/// (`runStructuredRequest`: de una vez o por partes, con su corrección) con
/// un modelo que contesta [reply] a cada llamada, y las anota.
class ScriptedWriter implements StructuredWriter {
  ScriptedWriter({required this.reply, this.contextTokens = 100000});

  final String Function(StructuredCall call) reply;

  @override
  final int contextTokens;

  final calls = <StructuredCall>[];
  final requests = <StructuredRequest<Object?>>[];

  @override
  Future<T> writeStructured<T>(StructuredRequest<T> request) {
    requests.add(request);
    return runStructuredRequest(request, (call) async {
      calls.add(call);
      return reply(call);
    });
  }
}

/// La lámina de muestra con todos sus pedidos de ilustración, como la
/// escribiría la IA: en JSON.
String sampleReply({bool illustrations = true}) => InfographicJson.encodeString(
  sampleInfographic(illustrations: illustrations),
);

/// La lámina de muestra, leída como la lee el generador.
Infographic sampleSheet({bool illustrations = true}) =>
    InfographicJson.decode(sampleReply(illustrations: illustrations));
