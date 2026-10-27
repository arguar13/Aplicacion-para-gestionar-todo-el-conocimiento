import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/features/ai_models/data/cloud/cloud_model_catalog.dart';
import 'package:sinapsis/features/ai_models/data/cloud/cloud_wire.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_account.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_model_settings.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_notice.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/cloud_model_exception.dart';
import 'package:sinapsis/features/ai_models/domain/repositories/ai_account_repository.dart';
import 'package:sinapsis/features/ai_models/domain/repositories/ai_usage_ledger.dart';
import 'package:sinapsis/features/ai_models/domain/services/quota_day.dart';
import 'package:sinapsis/features/chat/domain/entities/language_model_performance.dart';
import 'package:sinapsis/features/chat/domain/services/chat_model.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_gate.dart';
import 'package:sinapsis/features/chat/domain/services/language_model_meter.dart';
import 'package:sinapsis/features/chat/domain/services/model_backend.dart';

/// La ventana que se supone si la lista del proveedor no la dijo: holgada para
/// cualquier tarea de la app, y lejos de los topes por minuto de la capa
/// gratuita.
const kCloudDefaultContextTokens = 128000;

/// Lo más que se espera en silencio por el tope por minuto antes de tomar la
/// cuenta como agotada: más que eso, conviene probar con otra.
const kMaxRateLimitWait = Duration(seconds: 60);

/// Cuántos intentos se hacen por pedido y por cuenta (F39), contando el
/// primero: ante algo pasajero —la red que se cae un momento, el servicio
/// ocupado, la respuesta que se corta, el tope por minuto— se repite hasta
/// tres veces más antes de contárselo a la persona. Pasar a otra cuenta
/// empieza de nuevo.
const kCloudMaxAttempts = 4;

/// La espera antes del segundo intento; después se duplica (3, 6, 12 s…).
/// Alcanza para que el teléfono cambie de wifi a datos o el servicio respire,
/// sin hacer esperar de más.
const kCloudRetryBase = Duration(seconds: 3);

/// Lo máximo que dura una espera entre intentos.
const kCloudRetryCap = Duration(seconds: 30);

/// La espera antes de volver a intentar tras fallar el intento [attempt]
/// (1 es el primero): [kCloudRetryBase] duplicada cada vez, con un jitter de
/// ±25 % según [jitter] (de 0 a 1) para que varios pedidos que fallaron
/// juntos no vuelvan a la vez.
Duration cloudRetryDelay(
  int attempt, {
  double jitter = 0.5,
  Duration base = kCloudRetryBase,
  Duration cap = kCloudRetryCap,
}) {
  final raw = base.inMilliseconds * pow(2, attempt - 1) * (0.75 + 0.5 * jitter);
  final millis = min(raw, cap.inMilliseconds.toDouble());
  return Duration(milliseconds: millis.round());
}

/// Cuánto se deja de lado una cuenta cuya clave no anda, antes de volver a
/// probarla (por si se arregló del lado del proveedor).
const kRejectedKeyCooldown = Duration(minutes: 10);

/// Cuánto se deja de lado una cuenta paga sin saldo antes de volver a probar.
const kPaidQuotaCooldown = Duration(hours: 1);

/// Espera [duration] o hasta que se corte [cancel]: `false` si se cortó.
typedef CloudWait =
    Future<bool> Function(Duration duration, CancelToken? cancel);

/// [CloudWait] de verdad.
Future<bool> waitOrCancel(Duration duration, CancelToken? cancel) async {
  final done = Completer<bool>();
  final timer = Timer(duration, () {
    if (!done.isCompleted) done.complete(true);
  });
  unawaited(
    cancel?.whenCancel.then((_) {
      timer.cancel();
      if (!done.isCompleted) done.complete(false);
    }),
  );
  return done.future;
}

/// [ModelBackend] de un modelo en la nube (F32): Gemini por defecto, o OpenAI
/// o Claude, según el [CloudWire] que tenga.
///
/// Además de mandar cada pedido, decide **con qué cuenta**:
///
/// - Usa la cuenta elegida del proveedor; si no hay, la primera.
/// - Si el proveedor dice que se terminó la cuota del día (o el saldo), la
///   marca agotada hasta su renovación y —si `autoSwitchAccounts`, la decisión
///   B del usuario— pasa sola a la siguiente que tenga cuota, la deja como la
///   elegida y avisa ([AccountSwitchedNotice]). Lo mismo si la clave no anda.
/// - Si se pasó el tope por minuto, espera lo que pide el proveedor (hasta
///   [kMaxRateLimitWait]) avisando cuánto ([RateLimitWaitNotice]).
/// - Si falla algo pasajero (sin conexión, la espera vencida, la respuesta
///   cortada, el servicio ocupado), repite con la misma cuenta, hasta
///   [kCloudMaxAttempts] intentos, con espera creciente y jitter
///   ([cloudRetryDelay]) o la que pida el proveedor, y avisa cada vez
///   ([AiRetryNotice]). Una respuesta cortada a mitad se pide entera de nuevo
///   y avisa con `CloudDelta.restart` que lo escrito se descarta. Lo que no
///   pasa esperando (la clave, el pedido, la cuota del día) no se repite.
/// - Si no queda ninguna con cuota, lo dice ([AllAccountsExhaustedNotice]) y
///   el pedido falla con la hora de la renovación más cercana. Nunca cambia de
///   proveedor ni de modelo por su cuenta.
/// - Nunca cambia de cuenta a mitad de una respuesta: si algo falla después de
///   escribir y no es pasajero, se informa el error y lo escrito queda.
///
/// Cuenta lo gastado de cada cuenta ([AiUsageLedger]) y, la de la IA de fondo
/// ([forBackground]), lo topea por día.
class CloudModelBackend implements ModelBackend {
  CloudModelBackend({
    required CloudWire wire,
    required CloudModelCatalog catalog,
    required AiAccountRepository accounts,
    required AiUsageLedger usage,
    required AiModelSettings Function() settings,
    required Future<void> Function(AiModelSettings settings) saveSettings,
    required void Function(AiNotice notice) notify,
    required LanguageModelGate gate,
    required LanguageModelMeter meter,
    required Clock clock,
    CloudWait wait = waitOrCancel,
    double Function()? jitter,
  }) : this._(
         wire,
         catalog,
         accounts,
         usage,
         settings,
         saveSettings,
         notify,
         gate,
         meter,
         clock,
         wait,
         jitter ?? Random().nextDouble,
         background: false,
       );

  CloudModelBackend._(
    this._wire,
    this._catalog,
    this._accounts,
    this._usage,
    this._settings,
    this._saveSettings,
    this._notify,
    this._gate,
    this._meter,
    this._clock,
    this._wait,
    this._jitter, {
    required bool background,
  }) : _background = background;

  final CloudWire _wire;
  final CloudModelCatalog _catalog;
  final AiAccountRepository _accounts;
  final AiUsageLedger _usage;
  final AiModelSettings Function() _settings;
  final Future<void> Function(AiModelSettings settings) _saveSettings;
  final void Function(AiNotice notice) _notify;
  final LanguageModelGate _gate;
  final LanguageModelMeter _meter;
  final Clock _clock;
  final CloudWait _wait;

  /// De 0 a 1: el azar de la espera entre intentos (inyectable en pruebas).
  final double Function() _jitter;
  final bool _background;

  AiProvider get provider => _wire.provider;

  @override
  late final ModelBackend forBackground = _background
      ? this
      : CloudModelBackend._(
          _wire,
          _catalog,
          _accounts,
          _usage,
          _settings,
          _saveSettings,
          _notify,
          _gate,
          _meter,
          _clock,
          _wait,
          _jitter,
          background: true,
        );

  @override
  int get contextTokens {
    final model =
        _settings().modelOf(provider) ?? _catalog.recommended(provider);
    if (model == null) return kCloudDefaultContextTokens;
    return _catalog.info(provider, model)?.inputTokens ??
        kCloudDefaultContextTokens;
  }

  @override
  bool get isWarm => true;

  @override
  Future<void> warmUp() async {}

  @override
  Future<ModelExchange> openExchange({
    required String instruction,
    required int maxOutputTokens,
  }) async => _CloudExchange(this, instruction, maxOutputTokens);

  @override
  Future<ModelConversation> openConversation({
    required String instruction,
    required int maxOutputTokens,
  }) async => _CloudConversation(this, instruction, maxOutputTokens);

  /// La respuesta a [messages], con la cuenta que toque (ver la clase).
  /// [thinkMore] es «Pensar más» (F42): ver `CloudRequest.thinkMore`.
  Stream<CloudDelta> run({
    required String instruction,
    required List<CloudMessage> messages,
    required int maxOutputTokens,
    required LanguageModelReplyKind kind,
    CancelToken? cancel,
    bool thinkMore = false,
  }) async* {
    final tried = <String>{};
    // El intento de ahora con esta cuenta (1 es el primero).
    var attempt = 1;
    var retrying = false;
    while (true) {
      if (cancel?.isCancelled ?? false) return;
      final pick = await _pick(tried);
      if (_background) await _checkBackgroundCap();
      final model = await _catalog.resolve(
        provider,
        _settings(),
        key: pick.key,
      );

      final watch = Stopwatch()..start();
      Duration? firstToken;
      var wrote = false;
      int? inputTokens;
      int? outputTokens;
      final text = StringBuffer();
      try {
        await for (final delta in _wire.stream(
          CloudRequest(
            model: model,
            instruction: instruction,
            messages: messages,
            maxOutputTokens: maxOutputTokens,
            thinkMore: thinkMore,
          ),
          key: pick.key,
          cancel: cancel,
        )) {
          if (retrying) {
            // El reintento anduvo: ya llega la respuesta.
            retrying = false;
            if (!_background) {
              _notify(AiRetryEndedNotice(at: _clock(), provider: provider));
            }
          }
          if (delta.text.isNotEmpty) {
            wrote = true;
            firstToken ??= watch.elapsed;
            text.write(delta.text);
          }
          inputTokens = delta.inputTokens ?? inputTokens;
          outputTokens = delta.outputTokens ?? outputTokens;
          yield delta;
        }
      } on CloudModelException catch (error) {
        final now = _clock();
        // Lo pasajero se repite con la misma cuenta, también si se cortó
        // después de escribir: la respuesta vuelve a empezar.
        final pause = attempt < kCloudMaxAttempts
            ? _retryPause(error, attempt)
            : null;
        if (pause != null && !(cancel?.isCancelled ?? false)) {
          if (!_background) {
            _notify(
              AiRetryNotice(
                at: now,
                provider: provider,
                failure: error.failure,
                attempt: attempt + 1,
                maxAttempts: kCloudMaxAttempts,
                wait: pause,
              ),
            );
          }
          if (error.failure == CloudModelFailure.rateLimited) {
            _notify(
              RateLimitWaitNotice(at: now, account: pick.account, wait: pause),
            );
          }
          retrying = true;
          if (!await _wait(pause, cancel)) return;
          if (wrote) yield const CloudDelta(restart: true);
          attempt++;
          continue;
        }
        if (wrote) {
          // Lo escrito queda y no se sigue con otra cuenta; si fue la cuota,
          // la cuenta queda marcada para el pedido siguiente.
          if (error.failure == CloudModelFailure.quotaExhausted) {
            await _exhaust(
              pick.account,
              now.add(error.retryAfter ?? _defaultQuotaWait(now)),
              error.failure,
              tried,
            );
          }
          _failed(error);
          rethrow;
        }
        switch (error.failure) {
          case CloudModelFailure.rateLimited:
            // Pide esperar demasiado, o ya se esperó todo lo que se podía:
            // para esta respuesta, la cuenta está agotada.
            final wait = error.retryAfter ?? kMaxRateLimitWait;
            await _exhaust(pick.account, now.add(wait), error.failure, tried);
            if (!_settings().autoSwitchAccounts) {
              _notify(
                AllAccountsExhaustedNotice(
                  at: now,
                  provider: provider,
                  accounts: 1,
                  resetsAt: now.add(wait),
                ),
              );
              rethrow;
            }
            attempt = 1;
            continue;
          case CloudModelFailure.quotaExhausted:
            final until = now.add(error.retryAfter ?? _defaultQuotaWait(now));
            await _exhaust(pick.account, until, error.failure, tried);
            if (!_settings().autoSwitchAccounts) {
              _notify(
                AllAccountsExhaustedNotice(
                  at: now,
                  provider: provider,
                  accounts: 1,
                  resetsAt: until,
                ),
              );
              rethrow;
            }
            attempt = 1;
            continue;
          case CloudModelFailure.invalidKey || CloudModelFailure.forbidden:
            _notify(
              AccountKeyRejectedNotice(
                at: now,
                account: pick.account,
                reason: error.failure,
              ),
            );
            await _exhaust(
              pick.account,
              now.add(kRejectedKeyCooldown),
              error.failure,
              tried,
            );
            if (!_settings().autoSwitchAccounts) rethrow;
            attempt = 1;
            continue;
          // Lo demás (el modelo no existe, el pedido no entra, lo bloqueado,
          // lo pasajero que ya se reintentó) no lo arregla otra cuenta: va a
          // quien pidió.
          // ignore: no_default_cases
          default:
            _failed(error);
            rethrow;
        }
      } on DioException catch (error) {
        // Cortar mientras espera las cabeceras sale de Dio como cancelación:
        // es lo pedido, no una falla.
        if (CancelToken.isCancel(error)) return;
        rethrow;
      }

      // Salió bien.
      final now = _clock();
      await _usage.recordRequest(
        pick.account.id,
        now: now,
        inputTokens: inputTokens ?? 0,
        outputTokens: outputTokens ?? 0,
        background: _background,
      );
      await _usage.clearExhausted(pick.account.id, now: now);
      watch.stop();
      _meter.recordReply(
        LanguageModelReply(
          kind: kind,
          firstToken: firstToken,
          total: watch.elapsed,
          tokens: outputTokens,
          inputTokens: inputTokens,
          words: countWords(text.toString()),
        ),
      );
      return;
    }
  }

  /// Cuánto esperar antes de repetir el pedido que falló con [error] en el
  /// intento [attempt], o `null` si repetir no tiene sentido (F39): la clave,
  /// el pedido y la cuota del día no cambian por esperar, y un proveedor que
  /// pide esperar más de [kMaxRateLimitWait] se resuelve con otra cuenta.
  ///
  /// El tope por minuto espera lo que pide el proveedor, ni más ni menos; lo
  /// demás, el [cloudRetryDelay] o lo que pida el proveedor si es más.
  Duration? _retryPause(CloudModelException error, int attempt) {
    final limited = error.failure == CloudModelFailure.rateLimited;
    if (!limited && !error.isTransient) return null;
    final asked = error.retryAfter;
    if (asked != null && asked > kMaxRateLimitWait) return null;
    final backoff = cloudRetryDelay(attempt, jitter: _jitter());
    if (limited) return asked ?? backoff;
    return asked != null && asked > backoff ? asked : backoff;
  }

  /// Cuenta por qué falló un pedido de la persona; la IA de fondo no avisa:
  /// su estado lo muestra la cola.
  void _failed(CloudModelException error) {
    if (_background) return;
    _notify(
      AiRequestFailedNotice(
        at: _clock(),
        provider: provider,
        failure: error.failure,
      ),
    );
  }

  Duration _defaultQuotaWait(DateTime now) => provider == AiProvider.gemini
      ? nextQuotaReset(now).difference(now.toUtc())
      : kPaidQuotaCooldown;

  Future<void> _exhaust(
    AiAccount account,
    DateTime until,
    CloudModelFailure failure,
    Set<String> tried,
  ) async {
    tried.add(account.id);
    await _usage.markExhausted(
      account.id,
      now: _clock(),
      until: until,
      failure: failure,
    );
  }

  /// La cuenta con que se pide y su clave (ver la clase). [tried] son las que
  /// ya fallaron en este mismo pedido.
  Future<({AiAccount account, String key})> _pick(Set<String> tried) async {
    final now = _clock();
    final all = [
      for (final account in await _accounts.list())
        if (account.provider == provider) account,
    ];
    if (all.isEmpty) {
      throw const CloudModelException(CloudModelFailure.noAccount);
    }
    final settings = _settings();
    final activeId = settings.activeAccountOf(provider);
    final start = all.indexWhere((a) => a.id == activeId);
    final active = all[start < 0 ? 0 : start];

    final candidates = settings.autoSwitchAccounts
        ? [
            ...all.skip(start < 0 ? 0 : start),
            ...all.take(start < 0 ? 0 : start),
          ]
        : [active];
    for (final account in candidates) {
      if (tried.contains(account.id)) continue;
      if (_usage.usageOf(account.id, now: now).isExhaustedAt(now)) continue;
      final key = await _accounts.keyOf(account.id);
      if (key == null) continue;
      if (account.id != active.id) {
        await _saveSettings(settings.withActiveAccount(provider, account.id));
        final before = _usage.usageOf(active.id, now: now);
        _notify(
          AccountSwitchedNotice(
            at: now,
            from: active,
            to: account,
            reason: before.lastFailure ?? CloudModelFailure.quotaExhausted,
            fromResetsAt: before.exhaustedUntil,
          ),
        );
      }
      return (account: account, key: key);
    }

    // Ninguna sirve: la renovación más cercana, si se sabe.
    DateTime? resetsAt;
    for (final account in candidates) {
      final until = _usage.usageOf(account.id, now: now).exhaustedUntil;
      if (until != null && until.isAfter(now.toUtc())) {
        if (resetsAt == null || until.isBefore(resetsAt)) resetsAt = until;
      }
    }
    _notify(
      AllAccountsExhaustedNotice(
        at: now,
        provider: provider,
        accounts: candidates.length,
        resetsAt: resetsAt,
      ),
    );
    final lastFailure = _usage.usageOf(active.id, now: now).lastFailure;
    throw CloudModelException(
      lastFailure == CloudModelFailure.invalidKey ||
              lastFailure == CloudModelFailure.forbidden
          ? lastFailure!
          : CloudModelFailure.quotaExhausted,
      retryAfter: resetsAt?.difference(now.toUtc()),
    );
  }

  /// La IA de fondo no pasa de su tope del día, contando todas las cuentas del
  /// proveedor: lo que queda es para la persona.
  Future<void> _checkBackgroundCap() async {
    final now = _clock();
    final cap = _settings().backgroundDailyCap;
    var used = 0;
    for (final account in await _accounts.list()) {
      if (account.provider != provider) continue;
      used += _usage.usageOf(account.id, now: now).backgroundRequests;
    }
    if (used < cap) return;
    final resetsAt = nextQuotaReset(now);
    _notify(BackgroundCapReachedNotice(at: now, cap: cap, resetsAt: resetsAt));
    throw CloudModelException(
      CloudModelFailure.backgroundCap,
      retryAfter: resetsAt.difference(now.toUtc()),
    );
  }
}

/// Lo que ocupa un texto en tokens, estimado sin el tokenizador del
/// proveedor: unos tres caracteres por token en español, contando de más. Solo
/// sirve para no pasarse de la ventana, que en la nube es enorme.
int estimateCloudTokens(String text) => (text.length / 3).ceil();

/// Un pedido de una vuelta en la nube.
class _CloudExchange implements ModelExchange {
  _CloudExchange(this._backend, this._instruction, this._maxOutputTokens);

  final CloudModelBackend _backend;
  final String _instruction;
  final int _maxOutputTokens;
  CancelToken? _cancel;

  @override
  Future<int> countTokens(String text) async => estimateCloudTokens(text);

  @override
  Future<String> reply(
    String text, {
    LanguageModelReplyKind kind = LanguageModelReplyKind.task,
  }) async {
    final cancel = _cancel = CancelToken();
    final out = StringBuffer();
    await for (final delta in _backend.run(
      instruction: _instruction,
      messages: [CloudMessage(role: CloudRole.user, text: text)],
      maxOutputTokens: _maxOutputTokens,
      kind: kind,
      cancel: cancel,
    )) {
      // Se cortó y se pidió de nuevo entera: lo escrito no vale.
      if (delta.restart) out.clear();
      out.write(delta.text);
    }
    return out.toString().trim();
  }

  @override
  Future<void> stop() async => _cancel?.cancel();

  @override
  Future<void> close() async => _cancel?.cancel();
}

/// Una charla en la nube: el proveedor no recuerda nada (así no guarda nada),
/// así que cada mensaje lleva lo conversado antes.
class _CloudConversation implements ModelConversation {
  _CloudConversation(this._backend, this._instruction, this._maxOutputTokens);

  final CloudModelBackend _backend;
  final String _instruction;
  final int _maxOutputTokens;

  final _turns = <({String said, String answer})>[];
  CancelToken? _writing;
  var _closed = false;

  @override
  ChatReplyStream send({
    required String prompt,
    required String said,
    List<Uint8List> images = const [],
    bool thinkMore = false,
  }) {
    final cancel = CancelToken();
    late final StreamController<String> out;
    out = StreamController<String>(
      onListen: () =>
          unawaited(_write(prompt, said, images, thinkMore, out, cancel)),
      onCancel: cancel.cancel,
    );
    return out.stream;
  }

  Future<void> _write(
    String prompt,
    String said,
    List<Uint8List> images,
    bool thinkMore,
    StreamController<String> out,
    CancelToken cancel,
  ) async {
    final text = StringBuffer();
    var last = '';
    void give(String value) {
      if (cancel.isCancelled || value == last) return;
      last = value;
      out.add(value);
    }

    try {
      // En el turno de la persona: la IA de fondo espera mientras se escribe
      // (con la nube no se pisan, pero comparten la cuota por minuto).
      await _backend._gate.runForUser(() async {
        if (_closed || cancel.isCancelled) return;
        _writing = cancel;
        try {
          await for (final delta in _backend.run(
            instruction: _instruction,
            messages: [
              for (final turn in _history()) ...[
                CloudMessage(role: CloudRole.user, text: turn.said),
                CloudMessage(role: CloudRole.model, text: turn.answer),
              ],
              CloudMessage(role: CloudRole.user, text: prompt, images: images),
            ],
            maxOutputTokens: _maxOutputTokens,
            kind: LanguageModelReplyKind.chat,
            cancel: cancel,
            thinkMore: thinkMore,
          )) {
            if (delta.restart) text.clear();
            if (delta.text.isEmpty) continue;
            text.write(delta.text);
            give(text.toString().trimLeft());
          }
        } finally {
          _writing = null;
        }
      });
      final answer = text.toString().trim();
      if (answer.isNotEmpty) {
        give(answer);
        _turns.add((
          said: images.isEmpty ? said : '$said [con ${images.length} foto(s)]',
          answer: answer,
        ));
      }
      // El error va a quien escucha la respuesta, que es quien sabe mostrarlo.
      // ignore: avoid_catches_without_on_clauses
    } catch (error, stackTrace) {
      if (!cancel.isCancelled) out.addError(error, stackTrace);
    } finally {
      await out.close();
    }
  }

  /// Lo conversado que entra con holgura en la ventana: de lo más nuevo a lo
  /// más viejo, hasta la mitad de lo que el modelo lee de una vez.
  List<({String said, String answer})> _history() {
    var room = _backend.contextTokens ~/ 2;
    final kept = <({String said, String answer})>[];
    for (final turn in _turns.reversed) {
      final cost =
          estimateCloudTokens(turn.said) + estimateCloudTokens(turn.answer);
      if (cost > room) break;
      room -= cost;
      kept.insert(0, turn);
    }
    return kept;
  }

  @override
  Future<void> close() async {
    _closed = true;
    _writing?.cancel();
  }
}
