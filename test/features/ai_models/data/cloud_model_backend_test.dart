import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/ai_models/data/cloud/cloud_model_backend.dart';
import 'package:sinapsis/features/ai_models/data/cloud/cloud_model_catalog.dart';
import 'package:sinapsis/features/ai_models/data/cloud/cloud_wire.dart';
import 'package:sinapsis/features/ai_models/data/repositories/prefs_ai_usage_ledger.dart';
import 'package:sinapsis/features/ai_models/data/repositories/secure_ai_account_repository.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_account.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_model_settings.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_notice.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_info.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_gate.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_meter.dart';
import 'package:sinapsis/features/chat/domain/services/model_backend.dart';

class _Ids implements IdGenerator {
  var _n = 0;

  @override
  String next() => 'cuenta${++_n}';
}

/// Una respuesta que escribe y después falla.
class _Partial {
  const _Partial(this.chunks, this.error);
  final List<String> chunks;
  final CloudModelException error;
}

/// Un proveedor de mentira: por cada clave, lo que contesta en cada pedido
/// (una lista de pedazos de texto, un error, o [_Partial]).
class _FakeWire implements CloudWire {
  final scripts = <String, List<Object>>{};
  final calls = <({String key, CloudRequest request})>[];
  int listCalls = 0;
  List<CloudModelInfo> models = const [
    CloudModelInfo(id: 'gemini-3.5-flash-lite', displayName: 'Lite'),
    CloudModelInfo(
      id: 'gemini-3.8-flash',
      displayName: 'Flash',
      inputTokens: 1000000,
    ),
  ];

  /// Si está, el pedido espera esto antes de terminar (para cortarlo a mitad).
  Completer<void>? hold;

  @override
  AiProvider get provider => AiProvider.gemini;

  @override
  Future<List<CloudModelInfo>> listModels(String key) async {
    listCalls++;
    return models;
  }

  @override
  String? recommendedModel(List<CloudModelInfo> models) =>
      models.any((m) => m.id == 'gemini-3.8-flash')
      ? 'gemini-3.8-flash'
      : (models.isEmpty ? null : models.first.id);

  @override
  Stream<CloudDelta> stream(
    CloudRequest request, {
    required String key,
    CancelToken? cancel,
  }) async* {
    calls.add((key: key, request: request));
    final queue = scripts[key];
    if (queue == null || queue.isEmpty) {
      throw StateError('Nadie esperaba un pedido con $key');
    }
    final outcome = queue.removeAt(0);
    if (outcome is CloudModelException) throw outcome;
    if (outcome is _Partial) {
      for (final chunk in outcome.chunks) {
        yield CloudDelta(text: chunk);
      }
      throw outcome.error;
    }
    for (final chunk in outcome as List<String>) {
      if (cancel?.isCancelled ?? false) return;
      yield CloudDelta(text: chunk);
      if (hold != null) await hold!.future;
    }
    yield const CloudDelta(inputTokens: 100, outputTokens: 20);
  }
}

CloudModelException _quota({Duration? after}) =>
    CloudModelException(CloudModelFailure.quotaExhausted, retryAfter: after);

void main() {
  late _FakeWire wire;
  late SecureAiAccountRepository accounts;
  late PrefsAiUsageLedger usage;
  late CloudModelCatalog catalog;
  late AiModelSettings settings;
  late List<AiNotice> notices;
  late List<Duration> waits;
  late DateTime now;
  late CloudModelBackend backend;
  late AiAccount first;
  late AiAccount second;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    now = DateTime.utc(2026, 10, 16, 15);
    wire = _FakeWire();
    accounts = SecureAiAccountRepository(ids: _Ids(), clock: () => now);
    usage = PrefsAiUsageLedger(prefs: prefs);
    catalog = CloudModelCatalog(
      prefs: prefs,
      wires: {AiProvider.gemini: wire},
      clock: () => now,
    );
    settings = const AiModelSettings();
    notices = [];
    waits = [];
    backend = CloudModelBackend(
      wire: wire,
      catalog: catalog,
      accounts: accounts,
      usage: usage,
      settings: () => settings,
      saveSettings: (next) async => settings = next,
      notify: notices.add,
      gate: LanguageModelGate(),
      meter: LanguageModelMeter(),
      clock: () => now,
      wait: (duration, cancel) async {
        waits.add(duration);
        return !(cancel?.isCancelled ?? false);
      },
    );
    first = await accounts.add(
      provider: AiProvider.gemini,
      key: 'clave-1',
      label: 'armando@gmail.com',
    );
    now = now.add(const Duration(seconds: 1));
    second = await accounts.add(
      provider: AiProvider.gemini,
      key: 'clave-2',
      label: 'otra@gmail.com',
    );
  });

  Future<String> ask(ModelBackend on, [String text = 'Hola']) async {
    final exchange = await on.openExchange(
      instruction: 'Instrucción',
      maxOutputTokens: 64,
    );
    try {
      return await exchange.reply(text);
    } finally {
      await exchange.close();
    }
  }

  test('pide con la primera cuenta, con el modelo recomendado, y cuenta lo '
      'gastado', () async {
    wire.scripts['clave-1'] = [
      ['Hola, ', 'Armando.'],
    ];

    expect(await ask(backend), 'Hola, Armando.');

    expect(wire.calls.single.key, 'clave-1');
    expect(wire.calls.single.request.model, 'gemini-3.8-flash');
    expect(wire.calls.single.request.instruction, 'Instrucción');
    expect(wire.calls.single.request.maxOutputTokens, 64);
    final spent = usage.usageOf(first.id, now: now);
    expect(spent.requests, 1);
    expect(spent.backgroundRequests, 0);
    expect(spent.inputTokens, 100);
    expect(spent.outputTokens, 20);
    expect(notices, isEmpty);
  });

  test('la lista de modelos se pide una vez y se guarda; un modelo elegido '
      'manda', () async {
    wire.scripts['clave-1'] = [
      ['a'],
      ['b'],
      ['c'],
    ];
    await ask(backend);
    await ask(backend);
    expect(wire.listCalls, 1);

    settings = settings.withModel(AiProvider.gemini, 'gemini-3.5-flash-lite');
    await ask(backend);
    expect(wire.calls.last.request.model, 'gemini-3.5-flash-lite');
    expect(backend.contextTokens, kCloudDefaultContextTokens);
  });

  test('la ventana es la del modelo, si la lista la dice', () async {
    wire.scripts['clave-1'] = [
      ['a'],
    ];
    await ask(backend);
    expect(backend.contextTokens, 1000000);
  });

  group('cuando una cuenta se queda sin cuota', () {
    test('pasa sola a la siguiente, repite el pedido, la deja elegida y '
        'avisa', () async {
      wire
        ..scripts['clave-1'] = [_quota(after: const Duration(hours: 16))]
        ..scripts['clave-2'] = [
          ['Sigo con la otra.'],
        ];

      expect(await ask(backend, '¿Qué es Roma?'), 'Sigo con la otra.');

      expect(wire.calls.map((c) => c.key), ['clave-1', 'clave-2']);
      expect(wire.calls.last.request.messages.single.text, '¿Qué es Roma?');
      expect(settings.activeAccountOf(AiProvider.gemini), second.id);
      final notice = notices.single as AccountSwitchedNotice;
      expect(notice.from, first);
      expect(notice.to, second);
      expect(notice.reason, CloudModelFailure.quotaExhausted);
      expect(notice.fromResetsAt, DateTime.utc(2026, 10, 17, 7, 0, 1));
      expect(usage.usageOf(first.id, now: now).isExhaustedAt(now), isTrue);
    });

    test('el pedido siguiente va directo a la nueva', () async {
      wire
        ..scripts['clave-1'] = [_quota()]
        ..scripts['clave-2'] = [
          ['uno'],
          ['dos'],
        ];
      await ask(backend);
      notices.clear();

      expect(await ask(backend), 'dos');
      expect(wire.calls.map((c) => c.key), ['clave-1', 'clave-2', 'clave-2']);
      expect(notices, isEmpty);
    });

    test('sin hora del proveedor, la cuota de Gemini vuelve a la medianoche '
        'del Pacífico', () async {
      wire
        ..scripts['clave-1'] = [_quota()]
        ..scripts['clave-2'] = [
          ['ok'],
        ];
      await ask(backend);

      expect(
        usage.usageOf(first.id, now: now).exhaustedUntil,
        DateTime.utc(2026, 10, 17, 7),
      );
    });

    test('si se agotan todas, falla con la renovación más '
        'cercana y avisa', () async {
      wire
        ..scripts['clave-1'] = [_quota(after: const Duration(hours: 16))]
        ..scripts['clave-2'] = [_quota(after: const Duration(hours: 2))];

      try {
        await ask(backend);
        fail('no falló');
      } on CloudModelException catch (e) {
        expect(e.failure, CloudModelFailure.quotaExhausted);
        expect(e.retryAfter, const Duration(hours: 2));
      }
      final last = notices.last as AllAccountsExhaustedNotice;
      expect(last.accounts, 2);
      expect(last.resetsAt, now.add(const Duration(hours: 2)));
    });

    test('con todas agotadas, el pedido siguiente ni llama al '
        'proveedor', () async {
      wire
        ..scripts['clave-1'] = [_quota()]
        ..scripts['clave-2'] = [_quota()];
      await expectLater(ask(backend), throwsA(isA<CloudModelException>()));
      final calls = wire.calls.length;

      await expectLater(ask(backend), throwsA(isA<CloudModelException>()));
      expect(wire.calls.length, calls);
    });

    test('cuando se renueva, la primera vuelve a servir', () async {
      wire
        ..scripts['clave-1'] = [
          _quota(after: const Duration(hours: 1)),
          ['volví'],
        ]
        ..scripts['clave-2'] = [_quota(after: const Duration(hours: 3))];
      await expectLater(ask(backend), throwsA(isA<CloudModelException>()));
      expect(settings.activeAccountOf(AiProvider.gemini), second.id);

      // A la hora la primera ya se renovó; la segunda, no.
      now = now.add(const Duration(hours: 1, seconds: 1));
      expect(await ask(backend), 'volví');
      expect(wire.calls.last.key, 'clave-1');
      expect(settings.activeAccountOf(AiProvider.gemini), first.id);
      expect(usage.usageOf(first.id, now: now).lastFailure, isNull);
    });

    test('con el cambio automático apagado, no toca la otra cuenta', () async {
      settings = settings.copyWith(autoSwitchAccounts: false);
      wire.scripts['clave-1'] = [_quota()];

      await expectLater(
        ask(backend),
        throwsA(
          isA<CloudModelException>().having(
            (e) => e.failure,
            'failure',
            CloudModelFailure.quotaExhausted,
          ),
        ),
      );
      expect(wire.calls.map((c) => c.key), ['clave-1']);
      expect(settings.activeAccountOf(AiProvider.gemini), isNull);
      expect(notices.single, isA<AllAccountsExhaustedNotice>());
    });

    test('con el cambio automático apagado y la cuenta ya agotada, el pedido '
        'siguiente tampoco usa otra', () async {
      settings = settings.copyWith(autoSwitchAccounts: false);
      wire.scripts['clave-1'] = [_quota()];
      await expectLater(ask(backend), throwsA(isA<CloudModelException>()));
      notices.clear();

      await expectLater(
        ask(backend),
        throwsA(
          isA<CloudModelException>().having(
            (e) => e.failure,
            'failure',
            CloudModelFailure.quotaExhausted,
          ),
        ),
      );
      expect(wire.calls.map((c) => c.key), ['clave-1']);
      expect((notices.single as AllAccountsExhaustedNotice).accounts, 1);
    });

    test('empieza por la elegida y da la vuelta por las demás', () async {
      final third = await accounts.add(
        provider: AiProvider.gemini,
        key: 'clave-3',
      );
      settings = settings.withActiveAccount(AiProvider.gemini, second.id);
      wire
        ..scripts['clave-2'] = [_quota()]
        ..scripts['clave-3'] = [_quota()]
        ..scripts['clave-1'] = [
          ['la primera'],
        ];

      expect(await ask(backend), 'la primera');
      expect(wire.calls.map((c) => c.key), ['clave-2', 'clave-3', 'clave-1']);
      expect(settings.activeAccountOf(AiProvider.gemini), first.id);
      expect(third.label, 'Cuenta 3');
    });

    test('las cuentas de otros proveedores no cuentan', () async {
      await accounts.add(provider: AiProvider.openAi, key: 'sk-otra');
      wire
        ..scripts['clave-1'] = [_quota()]
        ..scripts['clave-2'] = [_quota()];

      await expectLater(ask(backend), throwsA(isA<CloudModelException>()));
      expect(wire.calls.map((c) => c.key), ['clave-1', 'clave-2']);
      expect((notices.last as AllAccountsExhaustedNotice).accounts, 2);
    });
  });

  group('el tope por minuto', () {
    test('espera lo que pide el proveedor, avisando, y repite '
        'con la misma', () async {
      wire.scripts['clave-1'] = [
        const CloudModelException(
          CloudModelFailure.rateLimited,
          retryAfter: Duration(seconds: 7),
        ),
        ['ya está'],
      ];

      expect(await ask(backend), 'ya está');
      expect(waits, [const Duration(seconds: 7)]);
      expect(wire.calls.map((c) => c.key), ['clave-1', 'clave-1']);
      final notice = notices.single as RateLimitWaitNotice;
      expect(notice.account, first);
      expect(notice.wait, const Duration(seconds: 7));
    });

    test('si pide esperar demasiado, sigue con otra cuenta', () async {
      wire
        ..scripts['clave-1'] = [
          const CloudModelException(
            CloudModelFailure.rateLimited,
            retryAfter: Duration(minutes: 5),
          ),
        ]
        ..scripts['clave-2'] = [
          ['con la otra'],
        ];

      expect(await ask(backend), 'con la otra');
      expect(waits, isEmpty);
      expect(notices.single, isA<AccountSwitchedNotice>());
    });

    test('no espera para siempre: a la cuarta, la toma por agotada', () async {
      const limited = CloudModelException(
        CloudModelFailure.rateLimited,
        retryAfter: Duration(seconds: 3),
      );
      wire
        ..scripts['clave-1'] = [limited, limited, limited, limited]
        ..scripts['clave-2'] = [
          ['al fin'],
        ];

      expect(await ask(backend), 'al fin');
      expect(waits, hasLength(kRateLimitRetries));
    });
  });

  test('una clave que no anda: avisa y sigue con la otra', () async {
    wire
      ..scripts['clave-1'] = [
        const CloudModelException(CloudModelFailure.invalidKey),
      ]
      ..scripts['clave-2'] = [
        ['ok'],
      ];

    expect(await ask(backend), 'ok');
    expect(notices.first, isA<AccountKeyRejectedNotice>());
    expect(
      (notices.first as AccountKeyRejectedNotice).reason,
      CloudModelFailure.invalidKey,
    );
    expect(notices.last, isA<AccountSwitchedNotice>());
    expect(
      (notices.last as AccountSwitchedNotice).reason,
      CloudModelFailure.invalidKey,
    );
  });

  test('nunca cambia de cuenta a mitad de una respuesta', () async {
    wire
      ..scripts['clave-1'] = [
        const _Partial([
          'Empecé a ',
        ], CloudModelException(CloudModelFailure.quotaExhausted)),
      ]
      ..scripts['clave-2'] = [
        ['no debería'],
      ];

    await expectLater(ask(backend), throwsA(isA<CloudModelException>()));
    expect(wire.calls.map((c) => c.key), ['clave-1']);
    expect(notices, isEmpty);
  });

  test('si el proveedor está saturado, reintenta una vez', () async {
    const busy = CloudModelException(CloudModelFailure.unavailable);
    wire.scripts['clave-1'] = [
      busy,
      ['ahora sí'],
    ];
    expect(await ask(backend), 'ahora sí');
    expect(waits, [kUnavailableRetryWait]);

    wire.scripts['clave-1'] = [busy, busy];
    await expectLater(ask(backend), throwsA(isA<CloudModelException>()));
  });

  test('sin cuentas: «no hay cuenta»', () async {
    await accounts.remove(first.id);
    await accounts.remove(second.id);

    await expectLater(
      ask(backend),
      throwsA(
        isA<CloudModelException>().having(
          (e) => e.failure,
          'failure',
          CloudModelFailure.noAccount,
        ),
      ),
    );
  });

  group('la IA de fondo', () {
    test('cuenta aparte y no pasa de su tope del día', () async {
      settings = settings.copyWith(backgroundDailyCap: 2);
      wire.scripts['clave-1'] = [
        ['1'],
        ['2'],
        ['de la persona'],
      ];

      await ask(backend.forBackground);
      await ask(backend.forBackground);
      await expectLater(
        ask(backend.forBackground),
        throwsA(
          isA<CloudModelException>().having(
            (e) => e.failure,
            'failure',
            CloudModelFailure.backgroundCap,
          ),
        ),
      );
      expect(notices.single, isA<BackgroundCapReachedNotice>());

      // La persona sigue pudiendo.
      expect(await ask(backend), 'de la persona');
      final spent = usage.usageOf(first.id, now: now);
      expect(spent.requests, 3);
      expect(spent.backgroundRequests, 2);
    });

    test('es la misma para la de fondo de la de fondo', () {
      expect(
        identical(backend.forBackground.forBackground, backend.forBackground),
        isTrue,
      );
    });
  });

  test('cortar a mitad termina con lo escrito', () async {
    wire
      ..hold = Completer<void>()
      ..scripts['clave-1'] = [
        ['primera parte', ' segunda parte'],
      ];
    final exchange = await backend.openExchange(
      instruction: 'x',
      maxOutputTokens: 64,
    );
    final reply = exchange.reply('Hola');
    await pumpEventQueue();
    await exchange.stop();
    wire.hold!.complete();

    expect(await reply, 'primera parte');
  });

  group('una charla', () {
    test('cada mensaje lleva lo conversado antes, sin el '
        'contexto viejo', () async {
      wire.scripts['clave-1'] = [
        ['Roma ', 'fue un imperio.'],
        ['Cayó en 476.'],
      ];
      final chat = await backend.openConversation(
        instruction: 'Charlá',
        maxOutputTokens: 512,
      );

      final first = await chat
          .send(prompt: 'Contexto: […]\n¿Qué es Roma?', said: '¿Qué es Roma?')
          .toList();
      expect(first.last, 'Roma fue un imperio.');
      // Cada evento es todo lo escrito hasta ahí, sin repetirse.
      expect(first, ['Roma ', 'Roma fue un imperio.']);

      final second = await chat
          .send(prompt: '¿Cuándo cayó?', said: '¿Cuándo cayó?')
          .toList();
      expect(second.last, 'Cayó en 476.');

      final messages = wire.calls.last.request.messages;
      expect(messages.map((m) => m.role), [
        CloudRole.user,
        CloudRole.model,
        CloudRole.user,
      ]);
      expect(messages.map((m) => m.text), [
        '¿Qué es Roma?',
        'Roma fue un imperio.',
        '¿Cuándo cayó?',
      ]);
      await chat.close();
    });

    test('un error llega a quien escucha', () async {
      wire
        ..scripts['clave-1'] = [_quota()]
        ..scripts['clave-2'] = [_quota()];
      final chat = await backend.openConversation(
        instruction: 'x',
        maxOutputTokens: 64,
      );

      await expectLater(
        chat.send(prompt: 'Hola', said: 'Hola').toList(),
        throwsA(isA<CloudModelException>()),
      );
      await chat.close();
    });
  });
}
