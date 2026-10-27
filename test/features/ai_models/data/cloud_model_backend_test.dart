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
    if (outcome is DioException) throw outcome;
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
  late LanguageModelMeter meter;
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
    meter = LanguageModelMeter();
    backend = CloudModelBackend(
      wire: wire,
      catalog: catalog,
      accounts: accounts,
      usage: usage,
      settings: () => settings,
      saveSettings: (next) async => settings = next,
      notify: notices.add,
      gate: LanguageModelGate(),
      meter: meter,
      clock: () => now,
      wait: (duration, cancel) async {
        waits.add(duration);
        return !(cancel?.isCancelled ?? false);
      },
      // Sin azar: la espera es la del medio, 3, 6, 12 s.
      jitter: () => 0.5,
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

  test('cada respuesta le cuenta al medidor los tokens que el proveedor contó, '
      'leídos y escritos, y a los oyentes en el acto (F39)', () async {
    wire.scripts['clave-1'] = [
      ['Hola, ', 'Armando.'],
    ];
    final heard = <(int?, int?)>[];
    meter.addTap((reply) => heard.add((reply.inputTokens, reply.tokens)));

    await ask(backend);

    final reply = meter.performance.value.taskReply!;
    expect((reply.inputTokens, reply.tokens), (100, 20));
    expect(heard, [(100, 20)]);
  });

  test('una respuesta que falló no cuenta tokens: solo lo que el proveedor '
      'contestó entero', () async {
    wire.scripts['clave-1'] = [
      const CloudModelException(CloudModelFailure.modelNotFound),
    ];
    final heard = <int?>[];
    meter.addTap((reply) => heard.add(reply.tokens));

    await expectLater(ask(backend), throwsA(isA<CloudModelException>()));

    expect(heard, isEmpty);
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
      final notice = notices.whereType<RateLimitWaitNotice>().single;
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
      // Cuatro intentos son tres esperas.
      expect(waits, hasLength(kCloudMaxAttempts - 1));
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
    // Dice por qué, y la cuenta queda agotada para el pedido siguiente.
    expect(
      notices.single,
      isA<AiRequestFailedNotice>().having(
        (n) => n.failure,
        'failure',
        CloudModelFailure.quotaExhausted,
      ),
    );
    expect(usage.usageOf(first.id, now: now).isExhaustedAt(now), isTrue);
  });

  group('lo pasajero se reintenta solo (F39)', () {
    const busy = CloudModelException(CloudModelFailure.unavailable);
    const offline = CloudModelException(CloudModelFailure.network);
    const slow = CloudModelException(CloudModelFailure.timeout);
    const cut = CloudModelException(CloudModelFailure.cutOff);

    for (final transient in [busy, offline, slow, cut]) {
      test('${transient.failure.name}: espera creciente y sigue', () async {
        wire.scripts['clave-1'] = [
          transient,
          transient,
          ['ahora sí'],
        ];

        expect(await ask(backend), 'ahora sí');

        // 3 s y 6 s: se duplica.
        expect(waits, [const Duration(seconds: 3), const Duration(seconds: 6)]);
        // Siempre con la misma cuenta.
        expect(wire.calls.map((c) => c.key), ['clave-1', 'clave-1', 'clave-1']);
        // La cuenta anda: no se la deja de lado.
        expect(usage.usageOf(first.id, now: now).isExhaustedAt(now), isFalse);
      });
    }

    test('dice «Reintentando (2 de 4)», y que ya anduvo', () async {
      wire.scripts['clave-1'] = [
        busy,
        busy,
        ['ahora sí'],
      ];

      await ask(backend);

      final retries = notices.whereType<AiRetryNotice>().toList();
      expect(retries.map((n) => (n.attempt, n.maxAttempts, n.failure)), [
        (2, 4, CloudModelFailure.unavailable),
        (3, 4, CloudModelFailure.unavailable),
      ]);
      expect(retries.map((n) => n.wait), [
        const Duration(seconds: 3),
        const Duration(seconds: 6),
      ]);
      expect(retries.every((n) => n.provider == AiProvider.gemini), isTrue);
      // Y avisa cuando el reintento anduvo, una sola vez, y sin error final.
      expect(notices.whereType<AiRetryEndedNotice>(), hasLength(1));
      expect(notices.last, isA<AiRetryEndedNotice>());
      expect(notices.whereType<AiRequestFailedNotice>(), isEmpty);
    });

    test('se rinde a los cuatro intentos y cuenta la clase de falla', () async {
      wire.scripts['clave-1'] = [offline, offline, offline, offline];

      await expectLater(
        ask(backend),
        throwsA(
          isA<CloudModelException>().having(
            (e) => e.failure,
            'failure',
            CloudModelFailure.network,
          ),
        ),
      );

      expect(wire.calls, hasLength(kCloudMaxAttempts));
      expect(waits, [
        const Duration(seconds: 3),
        const Duration(seconds: 6),
        const Duration(seconds: 12),
      ]);
      expect(
        notices.last,
        isA<AiRequestFailedNotice>().having(
          (n) => n.failure,
          'failure',
          CloudModelFailure.network,
        ),
      );
      // Sin red no se cambia de cuenta.
      expect(wire.calls.map((c) => c.key).toSet(), {'clave-1'});
    });

    test('el jitter mueve la espera un cuarto para cada lado', () async {
      final seen = <Duration>[];
      for (final jitter in [0.0, 1.0]) {
        final jittered = CloudModelBackend(
          wire: wire,
          catalog: catalog,
          accounts: accounts,
          usage: usage,
          settings: () => settings,
          saveSettings: (next) async => settings = next,
          notify: (_) {},
          gate: LanguageModelGate(),
          meter: LanguageModelMeter(),
          clock: () => now,
          wait: (duration, cancel) async {
            seen.add(duration);
            return true;
          },
          jitter: () => jitter,
        );
        wire.scripts['clave-1'] = [
          busy,
          ['ok'],
        ];
        await ask(jittered);
      }
      expect(seen, [
        const Duration(milliseconds: 2250),
        const Duration(milliseconds: 3750),
      ]);
    });

    test('respeta lo que pide el proveedor si es más que la espera', () async {
      wire.scripts['clave-1'] = [
        const CloudModelException(
          CloudModelFailure.unavailable,
          retryAfter: Duration(seconds: 20),
        ),
        ['ok'],
      ];

      await ask(backend);
      expect(waits, [const Duration(seconds: 20)]);
    });

    test('si pide esperar más de un minuto, no se queda esperando', () async {
      wire.scripts['clave-1'] = [
        const CloudModelException(
          CloudModelFailure.unavailable,
          retryAfter: Duration(minutes: 10),
        ),
      ];

      await expectLater(ask(backend), throwsA(isA<CloudModelException>()));
      expect(waits, isEmpty);
      expect(wire.calls, hasLength(1));
    });

    test('una respuesta cortada a mitad vuelve a empezar entera y lo escrito '
        'antes se descarta', () async {
      wire.scripts['clave-1'] = [
        const _Partial(['Roma fue un ', 'impe'], cut),
        ['Roma fue un imperio.'],
      ];

      expect(await ask(backend), 'Roma fue un imperio.');
      expect(waits, [const Duration(seconds: 3)]);
      expect(wire.calls, hasLength(2));
    });

    test(
      'en una charla, el corte reemplaza lo escrito y no lo repite',
      () async {
        wire.scripts['clave-1'] = [
          const _Partial(['Roma fue '], cut),
          ['Roma fue un imperio.'],
        ];
        final chat = await backend.openConversation(
          instruction: 'x',
          maxOutputTokens: 64,
        );

        final seen = await chat.send(prompt: 'Hola', said: 'Hola').toList();

        expect(seen.last, 'Roma fue un imperio.');
        expect(seen.where((text) => text.contains('Roma fue Roma')), isEmpty);
        await chat.close();
      },
    );

    test('cortar mientras espera las cabeceras no es una falla', () async {
      wire.scripts['clave-1'] = [
        DioException.requestCancelled(
          requestOptions: RequestOptions(path: '/x'),
          reason: 'cortado',
        ),
      ];

      expect(await ask(backend), '');
      expect(notices, isEmpty);
    });

    test('se puede cancelar mientras espera', () async {
      var waiting = 0;
      final cancelling = CloudModelBackend(
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
          waiting++;
          return false;
        },
        jitter: () => 0.5,
      );
      wire.scripts['clave-1'] = [
        busy,
        ['no debería llegar'],
      ];

      expect(await ask(cancelling), '');
      expect(waiting, 1);
      expect(wire.calls, hasLength(1));
    });

    test('con varias cuentas, pasar a la otra empieza de nuevo la cuenta de '
        'intentos', () async {
      wire
        ..scripts['clave-1'] = [busy, busy, busy, _quota()]
        ..scripts['clave-2'] = [
          busy,
          busy,
          busy,
          ['con la otra'],
        ];

      expect(await ask(backend), 'con la otra');

      expect(wire.calls.map((c) => c.key), [
        'clave-1',
        'clave-1',
        'clave-1',
        'clave-1',
        'clave-2',
        'clave-2',
        'clave-2',
        'clave-2',
      ]);
    });

    test(
      'la IA de fondo reintenta igual pero no muestra «Reintentando»',
      () async {
        wire.scripts['clave-1'] = [
          busy,
          ['ok'],
        ];

        expect(await ask(backend.forBackground), 'ok');
        expect(waits, [const Duration(seconds: 3)]);
        expect(notices.whereType<AiRetryNotice>(), isEmpty);
        expect(notices.whereType<AiRetryEndedNotice>(), isEmpty);
      },
    );
  });

  group('lo que no pasa esperando no se reintenta (F39)', () {
    for (final failure in [
      CloudModelFailure.invalidKey,
      CloudModelFailure.forbidden,
      CloudModelFailure.badRequest,
      CloudModelFailure.modelNotFound,
      CloudModelFailure.blocked,
      CloudModelFailure.tooLong,
      CloudModelFailure.unknown,
    ]) {
      test(failure.name, () async {
        // Una sola cuenta, para ver solo lo que pasa con ella.
        settings = settings.copyWith(autoSwitchAccounts: false);
        wire.scripts['clave-1'] = [CloudModelException(failure)];

        await expectLater(ask(backend), throwsA(isA<CloudModelException>()));

        expect(wire.calls, hasLength(1));
        expect(waits, isEmpty);
        expect(notices.whereType<AiRetryNotice>(), isEmpty);
      });
    }

    test('la cuota agotada pasa a la otra cuenta sin esperar', () async {
      wire
        ..scripts['clave-1'] = [_quota()]
        ..scripts['clave-2'] = [
          ['con la otra'],
        ];

      expect(await ask(backend), 'con la otra');
      expect(waits, isEmpty);
      expect(notices.whereType<AiRetryNotice>(), isEmpty);
    });

    test('una cuota agotada a mitad de la respuesta no se reintenta ni '
        'cambia de cuenta', () async {
      wire.scripts['clave-1'] = [
        const _Partial([
          'Empecé ',
        ], CloudModelException(CloudModelFailure.quotaExhausted)),
      ];

      await expectLater(ask(backend), throwsA(isA<CloudModelException>()));
      expect(wire.calls, hasLength(1));
      expect(waits, isEmpty);
    });
  });

  test('lo que otra cuenta no arregla se le cuenta a la persona, con el '
      'motivo; a la IA de fondo no', () async {
    const offline = CloudModelException(CloudModelFailure.blocked);
    wire.scripts['clave-1'] = [offline, offline];

    await expectLater(ask(backend), throwsA(isA<CloudModelException>()));
    expect(
      notices.single,
      isA<AiRequestFailedNotice>()
          .having((n) => n.failure, 'failure', CloudModelFailure.blocked)
          .having((n) => n.provider, 'provider', AiProvider.gemini),
    );
    // Otra cuenta no lo arregla: no se cambia.
    expect(wire.calls.map((c) => c.key), ['clave-1']);

    notices.clear();
    await expectLater(
      ask(backend.forBackground),
      throwsA(isA<CloudModelException>()),
    );
    expect(notices, isEmpty);
  });

  test('si falla después de escribir algo que no pasa esperando, también se '
      'dice por qué', () async {
    wire.scripts['clave-1'] = [
      const _Partial(['Roma '], CloudModelException(CloudModelFailure.blocked)),
    ];
    await expectLater(ask(backend), throwsA(isA<CloudModelException>()));
    expect(notices.single, isA<AiRequestFailedNotice>());
  });

  test('sin el cambio automático, una cuenta con el tope por minuto largo '
      'avisa que no queda ninguna', () async {
    settings = settings.copyWith(autoSwitchAccounts: false);
    wire.scripts['clave-1'] = [
      const CloudModelException(
        CloudModelFailure.rateLimited,
        retryAfter: Duration(minutes: 5),
      ),
    ];
    await expectLater(ask(backend), throwsA(isA<CloudModelException>()));
    expect(
      notices.single,
      isA<AllAccountsExhaustedNotice>().having(
        (n) => n.resetsAt,
        'resetsAt',
        now.add(const Duration(minutes: 5)),
      ),
    );
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

    test('«Pensar más» (F42) llega al pedido de ese mensaje y no a los '
        'demás', () async {
      wire.scripts['clave-1'] = [
        ['Uno.'],
        ['Dos.'],
      ];
      final chat = await backend.openConversation(
        instruction: 'Charlá',
        maxOutputTokens: 512,
      );

      await chat.send(prompt: 'A', said: 'A', thinkMore: true).toList();
      await chat.send(prompt: 'B', said: 'B').toList();

      expect(wire.calls.map((call) => call.request.thinkMore), [true, false]);
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
