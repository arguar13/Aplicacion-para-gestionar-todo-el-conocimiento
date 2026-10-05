import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinapsis/core/database/database_provider.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/core/domain/entities/notebook_mode.dart';
import 'package:sinapsis/core/telemetry/telemetry_provider.dart';
import 'package:sinapsis/core/telemetry/telemetry_service.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/features/notebooks/data/services/notebook_topic_reader_impl.dart';
import 'package:sinapsis/features/notebooks/domain/entities/notebook.dart';
import 'package:sinapsis/features/notebooks/domain/repositories/notebook_repository.dart';
import 'package:sinapsis/features/notebooks/domain/services/notebook_suggestions.dart';
import 'package:sinapsis/features/notebooks/presentation/providers/notebook_providers.dart';

/// Los cuadernos sugeridos que la persona dijo «ahora no» (F30), por
/// `NotebookSuggestion.key`: queda recordado entre aperturas. Un tema o una
/// etiqueta que todavía no estaba cuando dijo «ahora no» sí se sugiere.
class NotebookSuggestionDismissals extends StateNotifier<Set<String>> {
  NotebookSuggestionDismissals({required SharedPreferences prefs})
    : _prefs = prefs,
      super((prefs.getStringList(prefsKey) ?? const []).toSet());

  static const prefsKey = 'notebook_suggestions_dismissed';

  final SharedPreferences _prefs;

  Future<void> dismiss(Iterable<String> keys) async {
    state = {...state, ...keys};
    await _prefs.setStringList(prefsKey, state.toList());
  }
}

final notebookSuggestionDismissalsProvider =
    StateNotifierProvider<NotebookSuggestionDismissals, Set<String>>(
      (ref) => NotebookSuggestionDismissals(
        prefs: ref.watch(sharedPreferencesProvider),
      ),
    );

final notebookTopicReaderProvider = Provider<NotebookTopicReader>(
  (ref) => NotebookTopicReaderImpl(
    database: ref.watch(appDatabaseProvider),
    telemetry: ref.watch(telemetryServiceProvider),
  ),
);

/// Los temas y las etiquetas con sus conteos, actualizándose solos.
final notebookTopicsProvider = StreamProvider.autoDispose<List<NotebookTopic>>(
  (ref) => ref.watch(notebookTopicReaderProvider).watchTopics(),
);

/// Los cuadernos que se pueden sugerir ahora (F30): se recalculan solos
/// cuando entra algo, cuando se crea o se borra un cuaderno y cuando se
/// descarta uno.
final notebookSuggestionsProvider =
    Provider.autoDispose<List<NotebookSuggestion>>((ref) {
      final topics = ref.watch(notebookTopicsProvider).valueOrNull;
      final existing = ref.watch(notebooksProvider).valueOrNull;
      if (topics == null || existing == null) return const [];
      return suggestNotebooks(
        topics: topics,
        existing: existing,
        dismissed: ref.watch(notebookSuggestionDismissalsProvider),
      );
    });

/// Un cuaderno sugerido, con lo que se va a crear.
@immutable
class SuggestedNotebookDraft {
  const SuggestedNotebookDraft({
    required this.suggestion,
    required this.name,
    this.description,
    this.checked = false,
  });

  final NotebookSuggestion suggestion;

  /// El nombre del tema o la etiqueta, o el que propuso la IA.
  final String name;

  /// La línea que propuso la IA, si aportó una. Es para elegir: un cuaderno
  /// no guarda descripción.
  final String? description;
  final bool checked;

  /// Si el nombre es el de la IA y no el del tema.
  bool get named => name != suggestion.topic.name;

  SuggestedNotebookDraft copyWith({
    String? name,
    String? description,
    bool? checked,
  }) => SuggestedNotebookDraft(
    suggestion: suggestion,
    name: name ?? this.name,
    description: description ?? this.description,
    checked: checked ?? this.checked,
  );
}

@immutable
class NotebookSuggestionsState {
  const NotebookSuggestionsState({
    this.drafts = const [],
    this.naming = false,
    this.namingFailed = false,
  });

  final List<SuggestedNotebookDraft> drafts;

  /// Si la IA está proponiendo nombres.
  final bool naming;
  final bool namingFailed;

  int get checkedCount => drafts.where((d) => d.checked).length;

  NotebookSuggestionsState copyWith({
    List<SuggestedNotebookDraft>? drafts,
    bool? naming,
    bool? namingFailed,
  }) => NotebookSuggestionsState(
    drafts: drafts ?? this.drafts,
    naming: naming ?? this.naming,
    namingFailed: namingFailed ?? this.namingFailed,
  );
}

/// La hoja de cuadernos sugeridos (F30): la persona elige cuáles crear, y
/// cada uno nace **por consulta** —un tema, o una etiqueta con sus ramas—, así
/// que se mantiene al día solo con lo que entra.
///
/// Si está el modelo de lenguaje, la IA propone un nombre y, si aporta, una
/// línea para cada uno, por tandas de [kNotebookNamingBatch]; mientras tanto
/// se ven con el nombre del tema. Sin él, o si falla, queda el nombre del
/// tema.
class NotebookSuggestionsController
    extends StateNotifier<NotebookSuggestionsState> {
  NotebookSuggestionsController({
    required List<NotebookSuggestion> suggestions,
    required NotebookTopicReader reader,
    required NotebookNamer namer,
    required Future<bool> Function() languageModelReady,
    required NotebookRepository notebooks,
    required TelemetryService telemetry,
  }) : _reader = reader,
       _namer = namer,
       _languageModelReady = languageModelReady,
       _notebooks = notebooks,
       _telemetry = telemetry,
       super(
         NotebookSuggestionsState(
           drafts: [
             for (final suggestion in suggestions)
               SuggestedNotebookDraft(
                 suggestion: suggestion,
                 name: suggestion.topic.name,
               ),
           ],
         ),
       );

  final NotebookTopicReader _reader;
  final NotebookNamer _namer;
  final Future<bool> Function() _languageModelReady;
  final NotebookRepository _notebooks;
  final TelemetryService _telemetry;

  /// Le pide nombres a la IA, si está el modelo de lenguaje.
  Future<void> nameWithAi() async {
    if (state.drafts.isEmpty || !await _languageModelReady() || !mounted) {
      return;
    }
    state = state.copyWith(naming: true);
    final drafts = state.drafts;
    try {
      for (
        var start = 0;
        start < drafts.length;
        start += kNotebookNamingBatch
      ) {
        final batch = drafts.sublist(
          start,
          (start + kNotebookNamingBatch).clamp(0, drafts.length),
        );
        final inputs = <NotebookNamingInput>[
          for (final draft in batch)
            (
              topic: draft.suggestion.topic.name,
              itemCount: draft.suggestion.topic.itemCount,
              titles: await _reader.sampleTitles(draft.suggestion),
            ),
        ];
        final names = await _namer.nameNotebooks(inputs);
        if (!mounted) return;
        state = state.copyWith(
          drafts: [
            for (final draft in state.drafts)
              if (batch.indexWhere(
                    (b) => b.suggestion.key == draft.suggestion.key,
                  )
                  case final i when i >= 0 && names[i] != null)
                draft.copyWith(
                  name: names[i]!.name,
                  description: names[i]!.description,
                )
              else
                draft,
          ],
        );
      }
      // El modelo es de terceros y puede fallar de formas sin un tipo propio:
      // queda registrado, la hoja lo dice y los nombres quedan como los del
      // tema.
      // ignore: avoid_catches_without_on_clauses
    } catch (error, stackTrace) {
      _telemetry.recordError(
        error,
        stackTrace,
        hint: 'NotebookSuggestionsController: nombrar los sugeridos',
      );
      if (mounted) state = state.copyWith(namingFailed: true);
    } finally {
      if (mounted) state = state.copyWith(naming: false);
    }
  }

  void toggle(String key) {
    state = state.copyWith(
      drafts: [
        for (final draft in state.drafts)
          if (draft.suggestion.key == key)
            draft.copyWith(checked: !draft.checked)
          else
            draft,
      ],
    );
  }

  /// Marca todos, o los desmarca si ya estaban todos.
  void toggleAll() {
    final all = state.checkedCount == state.drafts.length;
    state = state.copyWith(
      drafts: [for (final draft in state.drafts) draft.copyWith(checked: !all)],
    );
  }

  /// Crea los marcados, cada uno por consulta, y devuelve los cuadernos.
  Future<List<Notebook>> create() async {
    final created = <Notebook>[];
    for (final draft in state.drafts) {
      if (!draft.checked) continue;
      created.add(
        await _notebooks.create(
          name: draft.name,
          mode: NotebookMode.query,
          query: draft.suggestion.query,
        ),
      );
    }
    return created;
  }
}

/// La hoja de cuadernos sugeridos mientras está abierta, con los que había al
/// abrirla: lo que entre después no cambia la lista bajo los dedos.
final notebookSuggestionsControllerProvider =
    StateNotifierProvider.autoDispose<
      NotebookSuggestionsController,
      NotebookSuggestionsState
    >(
      (ref) => NotebookSuggestionsController(
        suggestions: ref.read(notebookSuggestionsProvider),
        reader: ref.watch(notebookTopicReaderProvider),
        namer: ref.watch(notebookNamerProvider),
        languageModelReady: () => ref.read(chatModelManagerProvider).isReady(),
        notebooks: ref.watch(notebookRepositoryProvider),
        telemetry: ref.watch(telemetryServiceProvider),
      ),
    );
