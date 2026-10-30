import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/core/domain/entities/study_mark_kind.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_material.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope_catalog.dart';
import 'package:sinapsis/features/creations/domain/entities/creation_scope_summary.dart';
import 'package:sinapsis/features/creations/domain/entities/study_creation_kind.dart';
import 'package:sinapsis/features/creations/presentation/providers/creation_queue_providers.dart';
import 'package:sinapsis/features/creations/presentation/providers/creations_providers.dart';
import 'package:sinapsis/features/processed/domain/entities/processed_query.dart';
import 'package:sinapsis/features/processed/presentation/providers/processed_providers.dart';
import 'package:sinapsis/features/study/presentation/providers/study_providers.dart'
    as study;

/// Sobre qué trabaja Repasar (F43): lo elegido en el selector de arriba, que
/// manda en toda la pantalla —«Para hoy», las tarjetas de crear y «Lo
/// creado»—. Dura lo que la app abierta, como el recorte de antes: volver de
/// una sesión o de un visor deja el mismo.
final repasarScopeProvider = StateProvider<CreationScope>(
  (ref) => const CreationScope.allProcessed(),
);

/// Elige [scope] en Repasar y lo suma a los recientes del selector.
void chooseRepasarScope(WidgetRef ref, CreationScope scope) {
  ref.read(repasarScopeProvider.notifier).state = scope;
  ref.read(recentCreationScopesProvider.notifier).remember(scope);
}

/// Los últimos recortes que se eligieron, el más reciente primero: los que
/// van arriba de la hoja del selector, como mucho tres de cada pestaña
/// (`kRecentScopesShown`, M11).
///
/// Mismo almacén que los límites del día: es una preferencia de este
/// teléfono, no un dato de la bóveda. Se guardan por su `storageKey`; uno que
/// ya no se entiende se olvida al leerlo.
class RecentCreationScopes extends StateNotifier<List<CreationScope>> {
  RecentCreationScopes({required SharedPreferences prefs})
    : _prefs = prefs,
      super(_read(prefs));

  /// Cuántos se recuerdan: más de los tres que se ven, para que cada pestaña
  /// tenga los suyos aunque lo último elegido sea de otra.
  static const max = 12;

  static const _key = 'repasar_recent_scopes';

  final SharedPreferences _prefs;

  static List<CreationScope> _read(SharedPreferences prefs) => [
    for (final key in prefs.getStringList(_key) ?? const <String>[])
      ?CreationScope.parse(key),
  ].take(max).toList();

  /// Pone [scope] primero. «Todo lo procesado» no se recuerda: es su propia
  /// pestaña, siempre a la vista.
  void remember(CreationScope scope) {
    if (scope.isAll) return;
    state = [
      scope,
      for (final s in state)
        if (s != scope) s,
    ].take(max).toList();
    _save();
  }

  /// Lo olvida: lo que apuntaba ya no existe.
  void forget(CreationScope scope) {
    if (!state.contains(scope)) return;
    state = [
      for (final s in state)
        if (s != scope) s,
    ];
    _save();
  }

  void _save() =>
      _prefs.setStringList(_key, [for (final s in state) s.storageKey]);
}

final recentCreationScopesProvider =
    StateNotifierProvider<RecentCreationScopes, List<CreationScope>>(
      (ref) =>
          RecentCreationScopes(prefs: ref.watch(sharedPreferencesProvider)),
    );

/// Lo último que se eligió en la hoja de cada tipo (punto 3 del plan): la
/// próxima vez abre así. El idioma es uno para todos: quien estudia en
/// inglés lo quiere en todas.
class CreationLastChoices {
  CreationLastChoices({required SharedPreferences prefs}) : _prefs = prefs;

  static const _languageKey = 'creation_last_language';
  static String _optionsKey(StudyCreationKind kind) =>
      'creation_last_options.${kind.storageKey}';

  final SharedPreferences _prefs;

  /// Las opciones guardadas de [kind]; vacías si nunca se eligió o si lo
  /// guardado no se entiende.
  Map<String, Object?> optionsOf(StudyCreationKind kind) {
    final raw = _prefs.getString(_optionsKey(kind));
    if (raw == null) return const {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, Object?> ? decoded : const {};
    } on FormatException {
      return const {};
    }
  }

  /// El idioma de la última, o `null` si nunca se eligió.
  String? get languageCode => _prefs.getString(_languageKey);

  Future<void> save(
    StudyCreationKind kind,
    Map<String, Object?> options,
    String languageCode,
  ) async {
    await _prefs.setString(_optionsKey(kind), jsonEncode(options));
    await _prefs.setString(_languageKey, languageCode);
  }
}

final creationLastChoicesProvider = Provider<CreationLastChoices>(
  (ref) => CreationLastChoices(prefs: ref.watch(sharedPreferencesProvider)),
);

/// Una lista de documentos como clave de un proveedor: dos con los mismos ids
/// en el mismo orden son la misma.
@immutable
class CreationSourceIds {
  const CreationSourceIds(this.ids);

  final List<String> ids;

  @override
  bool operator ==(Object other) =>
      other is CreationSourceIds && listEquals(other.ids, ids);

  @override
  int get hashCode => Object.hashAll(ids);
}

/// Unos recortes como clave de un proveedor: dos con los mismos, en cualquier
/// orden, son la misma.
@immutable
class CreationScopeKeys {
  const CreationScopeKeys(this.scopes);

  final Set<CreationScope> scopes;

  @override
  bool operator ==(Object other) =>
      other is CreationScopeKeys && setEquals(other.scopes, scopes);

  @override
  int get hashCode => Object.hashAllUnordered(scopes);
}

/// Lo que ofrece el selector (M11), con la línea de cada uno, al día: todos
/// los documentos y los cuadernos, y los temas de la clave —los de la
/// categoría elegida y los recientes—. Una lectura en lote, nunca una por
/// fila.
final creationScopeCatalogProvider = StreamProvider.autoDispose
    .family<CreationScopeCatalog, CreationScopeKeys>(
      (ref, key) =>
          ref.watch(creationScopeResolverProvider).watchCatalog(key.scopes),
    );

/// Los documentos procesados que tienen el texto buscado —en el título o en
/// cualquiera de sus partes, como busca Procesado—: lo que el buscador del
/// selector suma después de lo que lo tiene en el nombre. Una lectura por
/// búsqueda, nunca una por fila.
final creationScopeTextSearchProvider = FutureProvider.autoDispose
    .family<Set<String>, String>((ref, text) async {
      final ids = await ref
          .watch(processedRepositoryProvider)
          .matchingIds(ProcessedQuery(searchText: text));
      return ids.getOrElse((_) => const []).toSet();
    });

/// Los documentos procesados vivos de un recorte, lo tocado más
/// recientemente primero: lo que la hoja ofrece en «Fuentes».
final creationScopeDocumentIdsProvider = FutureProvider.autoDispose
    .family<List<String>, CreationScope>((ref, scope) async {
      final ids = await ref
          .watch(creationScopeResolverProvider)
          .documentIds(scope);
      return ids.getOrElse((_) => const []);
    });

/// Cómo está cada uno de unos documentos —también los que ya no existen, como
/// «fuente borrada»—: las fichas de las fuentes y las filas de «Fuentes».
final creationSourcesProvider = FutureProvider.autoDispose
    .family<List<CreationSource>, CreationSourceIds>((ref, key) async {
      final sources = await ref
          .watch(creationScopeResolverProvider)
          .sourcesOf(key.ids);
      return sources.getOrElse((_) => const []);
    });

/// Lo que se le pregunta al armado del material para estimar una creación:
/// sus fuentes y cuánto va a escribir la IA.
@immutable
class CreationMaterialRequest {
  const CreationMaterialRequest({
    required this.sourceIds,
    required this.outputTokens,
  });

  final CreationSourceIds sourceIds;
  final int outputTokens;

  @override
  bool operator ==(Object other) =>
      other is CreationMaterialRequest &&
      other.sourceIds == sourceIds &&
      other.outputTokens == outputTokens;

  @override
  int get hashCode => Object.hash(sourceIds, outputTokens);
}

/// El material que se le mandaría al modelo elegido —armado igual que en la
/// cola, para que entre en su ventana—: de ahí salen los tokens de lectura y
/// cuántos pedidos van por partes en «Uso de IA». `null` si no se pudo
/// armar.
final creationSheetMaterialProvider = FutureProvider.autoDispose
    .family<CreationMaterial?, CreationMaterialRequest>((ref, request) async {
      final contextTokens = ref.watch(structuredWriterProvider).contextTokens;
      final material = await ref
          .watch(creationMaterialBuilderProvider)
          .build(
            sourceIds: request.sourceIds.ids,
            budget: CreationBudget(
              contextTokens: contextTokens,
              reservedOutputTokens: request.outputTokens,
            ),
          );
      return material.getRight().toNullable();
    });

/// Cuántos documentos se leen, como mucho, para sugerir temas: lo tocado más
/// recientemente del recorte.
const kSuggestedTopicsDocuments = 4;

/// Cuántos temas sugeridos se muestran.
const kSuggestedTopicsShown = 6;

/// Los temas sugeridos de la hoja («+ Moisés y Faraón»): las palabras clave
/// que más se repiten en lo más reciente del recorte (F36, F41), sin repetir
/// mayúsculas ni tildes de más. Vacío si todavía no tienen palabras clave.
final creationSuggestedTopicsProvider = FutureProvider.autoDispose
    .family<List<String>, CreationScope>((ref, scope) async {
      final ids = await ref.watch(
        creationScopeDocumentIdsProvider(scope).future,
      );
      final processed = ref.watch(processedRepositoryProvider);
      final studies = ref.watch(study.studyRepositoryProvider);
      final counts = <String, ({String shown, int count})>{};
      for (final id in ids.take(kSuggestedTopicsDocuments)) {
        final text = (await processed.studyTextOf(id)).getRight().toNullable();
        if (text == null) continue;
        final studied = await studies.read(text.key);
        for (final mark in studied.of(StudyMarkKind.keyword)) {
          if (mark.end > text.content.length || mark.start >= mark.end) {
            continue;
          }
          final word = text.content
              .substring(mark.start, mark.end)
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
          if (word.length < 3) continue;
          final key = word.toLowerCase();
          final seen = counts[key];
          counts[key] = (
            shown: seen?.shown ?? word,
            count: (seen?.count ?? 0) + 1,
          );
        }
      }
      final ranked = counts.values.toList()
        ..sort((a, b) {
          final byCount = b.count.compareTo(a.count);
          return byCount != 0 ? byCount : a.shown.compareTo(b.shown);
        });
      return [for (final r in ranked.take(kSuggestedTopicsShown)) r.shown];
    });
