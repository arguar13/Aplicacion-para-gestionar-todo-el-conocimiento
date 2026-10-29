import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_account.dart';
import 'package:sinapsis/features/ai_models/domain/entities/illustration_provider.dart';
import 'package:sinapsis/features/ai_models/domain/repositories/image_account_repository.dart';

/// [ImageAccountRepository] sobre el almacén seguro del sistema, igual que
/// `SecureAiAccountRepository` (F32): la lista en una entrada, cada clave en
/// la suya —leer la lista para dibujar nunca trae una clave a la memoria—, y
/// las escrituras de a una.
class SecureImageAccountRepository implements ImageAccountRepository {
  SecureImageAccountRepository({
    required IdGenerator ids,
    required Clock clock,
    FlutterSecureStorage? storage,
  }) : _ids = ids,
       _clock = clock,
       _storage = storage ?? const FlutterSecureStorage();

  static const _listKey = 'ai_image_accounts_v1';
  static String _keyOf(String id) => 'ai_image_key_$id';

  final IdGenerator _ids;
  final Clock _clock;
  final FlutterSecureStorage _storage;

  final _changes = StreamController<List<IllustrationAccount>>.broadcast();

  Future<void> _queue = Future.value();

  Future<T> _serial<T>(Future<T> Function() work) {
    final run = _queue.then((_) => work());
    _queue = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  @override
  Future<List<IllustrationAccount>> list() async {
    final raw = await _storage.read(key: _listKey);
    if (raw == null || raw.isEmpty) return const [];
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      // Como en F32: ilegible se muestra vacía y la próxima la reescribe.
      return const [];
    }
    if (decoded is! List) return const [];
    final accounts = [
      for (final entry in decoded) ?IllustrationAccount.fromJson(entry),
    ]..sort((a, b) => a.addedAt.compareTo(b.addedAt));
    return List.unmodifiable(accounts);
  }

  @override
  Stream<List<IllustrationAccount>> watch() async* {
    yield await list();
    yield* _changes.stream;
  }

  Future<void> _save(List<IllustrationAccount> accounts) async {
    await _storage.write(
      key: _listKey,
      value: jsonEncode([for (final a in accounts) a.toJson()]),
    );
    _changes.add(List.unmodifiable(accounts));
  }

  @override
  Future<IllustrationAccount> add({
    required IllustrationProvider provider,
    required String key,
    String? label,
  }) => _serial(() async {
    if (provider != IllustrationProvider.huggingFace) {
      throw ArgumentError.value(
        provider,
        'provider',
        'Solo las cuentas propias de imágenes se guardan acá',
      );
    }
    final trimmedKey = key.trim();
    if (trimmedKey.isEmpty) {
      throw ArgumentError.value(key, 'key', 'La clave está vacía');
    }
    final accounts = await list();
    final name = label?.trim() ?? '';
    final ofProvider = accounts.where((a) => a.provider == provider).length;
    final account = IllustrationAccount(
      id: _ids.next(),
      provider: provider,
      label: name.isNotEmpty ? name : 'Hugging Face ${ofProvider + 1}',
      addedAt: _clock().toUtc(),
    );
    // Primero la clave, como en F32: si se corta, queda una clave suelta y
    // no una cuenta sin clave.
    await _storage.write(key: _keyOf(account.id), value: trimmedKey);
    await _save([...accounts, account]);
    return account;
  });

  @override
  Future<void> rename(String id, String label) => _serial(() async {
    final name = label.trim();
    if (name.isEmpty) return;
    final accounts = await list();
    if (!accounts.any((a) => a.id == id)) return;
    await _save([
      for (final a in accounts)
        if (a.id == id) a.copyWith(label: name) else a,
    ]);
  });

  @override
  Future<void> replaceKey(String id, String key) => _serial(() async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(key, 'key', 'La clave está vacía');
    }
    final accounts = await list();
    if (!accounts.any((a) => a.id == id)) return;
    await _storage.write(key: _keyOf(id), value: trimmed);
    _changes.add(accounts);
  });

  @override
  Future<void> remove(String id) => _serial(() async {
    final accounts = await list();
    await _save([
      for (final a in accounts)
        if (a.id != id) a,
    ]);
    await _storage.delete(key: _keyOf(id));
  });

  @override
  Future<String?> keyOf(String id) async {
    final key = await _storage.read(key: _keyOf(id));
    return key == null || key.isEmpty ? null : key;
  }
}
