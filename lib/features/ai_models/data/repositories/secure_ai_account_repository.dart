import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sinapsis/core/util/clock.dart';
import 'package:sinapsis/core/util/id_generator.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_account.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/repositories/ai_account_repository.dart';

/// [AiAccountRepository] sobre el almacén seguro del sistema (F32, decisión
/// C): el llavero de Android (Keystore) y su equivalente en cada plataforma,
/// el mismo donde vive la clave de la bóveda.
///
/// La lista de cuentas —con sus nombres, que pueden ser direcciones de
/// correo— va en una entrada; cada clave, en la suya: leer la lista para
/// dibujar el menú nunca trae una clave a la memoria.
class SecureAiAccountRepository implements AiAccountRepository {
  SecureAiAccountRepository({
    required IdGenerator ids,
    required Clock clock,
    FlutterSecureStorage? storage,
  }) : _ids = ids,
       _clock = clock,
       _storage = storage ?? const FlutterSecureStorage();

  static const _listKey = 'ai_accounts_v1';
  static String _keyOf(String id) => 'ai_key_$id';

  final IdGenerator _ids;
  final Clock _clock;
  final FlutterSecureStorage _storage;

  final _changes = StreamController<List<AiAccount>>.broadcast();

  /// Las escrituras, de a una: dos cambios seguidos leen la lista que dejó el
  /// anterior, no la misma.
  Future<void> _queue = Future.value();

  Future<T> _serial<T>(Future<T> Function() work) {
    final run = _queue.then((_) => work());
    _queue = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  @override
  Future<List<AiAccount>> list() async {
    final raw = await _storage.read(key: _listKey);
    if (raw == null || raw.isEmpty) return const [];
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      // Una lista ilegible no se puede arreglar desde acá; se muestra vacía y
      // la próxima cuenta que se agregue la reescribe. Las claves siguen ahí.
      return const [];
    }
    if (decoded is! List) return const [];
    final accounts = [for (final entry in decoded) ?AiAccount.fromJson(entry)]
      ..sort((a, b) => a.addedAt.compareTo(b.addedAt));
    return List.unmodifiable(accounts);
  }

  @override
  Stream<List<AiAccount>> watch() async* {
    yield await list();
    yield* _changes.stream;
  }

  Future<void> _save(List<AiAccount> accounts) async {
    await _storage.write(
      key: _listKey,
      value: jsonEncode([for (final a in accounts) a.toJson()]),
    );
    _changes.add(List.unmodifiable(accounts));
  }

  @override
  Future<AiAccount> add({
    required AiProvider provider,
    required String key,
    String? label,
  }) => _serial(() async {
    final trimmedKey = key.trim();
    if (trimmedKey.isEmpty) {
      throw ArgumentError.value(key, 'key', 'La clave está vacía');
    }
    final accounts = await list();
    final name = label?.trim() ?? '';
    final ofProvider = accounts.where((a) => a.provider == provider).length;
    final account = AiAccount(
      id: _ids.next(),
      provider: provider,
      label: name.isNotEmpty ? name : 'Cuenta ${ofProvider + 1}',
      addedAt: _clock().toUtc(),
    );
    // Primero la clave: si se corta en el medio, queda una clave suelta (que
    // nadie lista) y no una cuenta sin clave.
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
    // La lista no cambia, pero quien mira (lo gastado, el estado de la
    // cuenta) tiene que enterarse: una clave nueva puede andar.
    _changes.add(accounts);
  });

  @override
  Future<void> remove(String id) => _serial(() async {
    final accounts = await list();
    // Primero se saca de la lista: si se corta en el medio, queda una clave
    // suelta y no una cuenta que figura sin clave.
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
