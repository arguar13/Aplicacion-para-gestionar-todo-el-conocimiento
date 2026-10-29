import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/storage/storage_providers.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/ai_models_providers.dart';
import 'package:sinapsis/features/creations/data/services/creation_illustration_store.dart';

/// Dónde se guardan las ilustraciones con IA de «Lo creado»: las de la
/// infografía, el mazo y el cuestionario.
final creationIllustrationStoreProvider = Provider<CreationIllustrationStore>(
  (ref) => CreationIllustrationStore(ref.watch(fileStoreProvider)),
);

/// Los bytes de la ilustración guardada en `reference`, o `null` si ya no
/// está (su lugar se dibuja).
final creationIllustrationBytesProvider = FutureProvider.autoDispose
    .family<Uint8List?, String>(
      (ref, reference) =>
          ref.watch(creationIllustrationStoreProvider).read(reference),
    );

/// La cuenta que escribe ahora —la elegida del proveedor elegido, o la
/// primera—, o `null` con Gemma: con la que dibuja «Con tu IA actual» si no se
/// eligió otra. Es lo mismo que `creationTextSideProvider`, leído de una vez
/// y sin esperar a que se carguen las cuentas en pantalla (la cola genera
/// también sin nadie mirando).
Future<String?> creationTextAccountId(Ref ref) async {
  final settings = ref.read(aiModelSettingsProvider);
  final provider = settings.provider;
  if (!provider.isCloud) return null;
  final accounts = [
    for (final account in await ref.read(aiAccountRepositoryProvider).list())
      if (account.provider == provider) account,
  ];
  final chosen = settings.activeAccountOf(provider);
  return (accounts.where((a) => a.id == chosen).firstOrNull ??
          accounts.firstOrNull)
      ?.id;
}
