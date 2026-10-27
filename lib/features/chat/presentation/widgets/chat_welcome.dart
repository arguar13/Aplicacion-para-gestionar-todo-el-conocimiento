import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/domain/entities/chat_conversation_mode.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/chat/domain/services/chat_greeting.dart';
import 'package:sinapsis/features/chat/domain/services/chat_suggestions.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_suggestions_provider.dart';
import 'package:sinapsis/features/settings/presentation/providers/owner_name.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo que hace una sugerencia tocada: el `text` que va al campo y si se
/// manda en el acto (`send`) o queda para completarlo.
typedef ChatSuggestionPick = ({String text, bool send});

/// El chat vacío, que recibe (F42): un saludo grande y tranquilo —«Hola,
/// Armando. ¿Qué querés saber de lo tuyo?», o según la hora sin nombre—, las
/// sugerencias armadas con lo del dueño y, si el modelo todavía no puede
/// contestar, el aviso con lo que falta ([notice]).
///
/// El brillo del fondo no es de acá: va detrás de toda la pantalla, también
/// detrás del campo (`ChatAmbientGlow`).
///
/// Sin [onSuggestion] no muestra sugerencias: es el saludo de una
/// conversación ya creada que todavía no tiene mensajes.
class ChatWelcome extends ConsumerWidget {
  const ChatWelcome({
    required this.mode,
    this.notebookId,
    this.onSuggestion,
    this.notice,
    super.key,
  });

  final ChatConversationMode mode;

  /// El cuaderno al que se acota la pregunta, con la bóveda; `null` es toda.
  final String? notebookId;
  final ValueChanged<ChatSuggestionPick>? onSuggestion;
  final Widget? notice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final onSuggestion = this.onSuggestion;
    final suggestions = onSuggestion == null
        ? const <ChatSuggestion>[]
        : ref.watch(
            chatSuggestionsProvider((mode: mode, notebookId: notebookId)),
          );
    final emptyVault =
        onSuggestion != null &&
        mode == ChatConversationMode.vault &&
        suggestions.isEmpty;

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: constraints.maxHeight > 40
                ? constraints.maxHeight - 40
                : 0,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Greeting(mode: mode),
                  if (suggestions.isNotEmpty) ...[
                    const SizedBox(height: 32),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 10,
                      children: [
                        for (final suggestion in suggestions)
                          _SuggestionPill(
                            suggestion: suggestion,
                            onPick: onSuggestion!,
                          ),
                      ],
                    ),
                  ] else if (emptyVault) ...[
                    const SizedBox(height: 24),
                    Text(
                      l10n.chatSuggestionsEmptyVault,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (notice case final notice?) ...[
                    const SizedBox(height: 32),
                    notice,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// «Hola, Armando.» —o «Buen día.»— grande, con el degradé del tema, y la
/// pregunta debajo.
class _Greeting extends ConsumerWidget {
  const _Greeting({required this.mode});

  final ChatConversationMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Ya recortado, y `null` sin nombre (`OwnerNameNotifier.normalize`).
    final name = ref.watch(ownerNameProvider);
    final hello = name != null
        ? l10n.chatGreetingNamed(name)
        : switch (dayPartOf(ref.read(clockProvider)())) {
            DayPart.morning => l10n.chatGreetingMorning,
            DayPart.afternoon => l10n.chatGreetingAfternoon,
            DayPart.evening => l10n.chatGreetingEvening,
          };
    final question = mode == ChatConversationMode.vault
        ? l10n.chatGreetingVaultQuestion
        : l10n.chatGreetingFreeQuestion;

    final helloStyle = theme.textTheme.displaySmall?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: -0.5,
      height: 1.15,
      color: scheme.onSurface,
    );
    Widget helloText = Text(
      hello,
      key: const Key('chat-greeting'),
      textAlign: TextAlign.center,
      style: helloStyle,
    );
    // El saludo con el degradé del tema, del primario al terciario. Con
    // «alto contraste» del sistema, liso: un degradé baja el contraste en
    // alguna de sus puntas.
    if (!MediaQuery.highContrastOf(context)) {
      helloText = ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) => LinearGradient(
          colors: [scheme.primary, scheme.tertiary],
        ).createShader(bounds),
        child: helloText,
      );
    }

    return Semantics(
      header: true,
      // Una sola frase para el lector de pantalla, no dos pedazos.
      label: '$hello $question',
      excludeSemantics: true,
      child: Column(
        children: [
          helloText,
          const SizedBox(height: 8),
          Text(
            question,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionPill extends StatelessWidget {
  const _SuggestionPill({required this.suggestion, required this.onPick});

  final ChatSuggestion suggestion;
  final ValueChanged<ChatSuggestionPick> onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = chatSuggestionText(l10n, suggestion);
    final sends = suggestion.sendsAtOnce;
    // Lo que se completa se ve con «…», como lo que es: un comienzo.
    final label = sends ? text : '${text.trimRight()}…';

    return Semantics(
      button: true,
      hint: sends ? null : l10n.chatSuggestionFillHint,
      excludeSemantics: true,
      label: label,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Material(
          color: scheme.surfaceContainerHigh,
          shape: StadiumBorder(
            side: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: .6),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('chat-suggestion-$label'),
            onTap: () => onPick((text: text, send: sends)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_iconOf(suggestion), size: 18, color: scheme.primary),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lo que dice [suggestion] —lo que va al campo—, en el idioma de la app.
String chatSuggestionText(
  AppLocalizations l10n,
  ChatSuggestion suggestion,
) => switch (suggestion) {
  SummarizeItemSuggestion(:final title) => l10n.chatSuggestionSummarize(title),
  QuizMeSuggestion(:final title) => l10n.chatSuggestionQuizMe(title),
  AskItemSuggestion(:final title) => l10n.chatSuggestionAskWhatItSays(title),
  ExploreTopicSuggestion(:final topic) => l10n.chatSuggestionExploreTopic(
    topic,
  ),
  NotebookThemesSuggestion(:final notebook) =>
    l10n.chatSuggestionNotebookThemes(notebook),
  FreeStarterSuggestion(:final starter) => switch (starter) {
    FreeChatStarter.explain => l10n.chatSuggestionFreeExplain,
    FreeChatStarter.brainstorm => l10n.chatSuggestionFreeBrainstorm,
    FreeChatStarter.draft => l10n.chatSuggestionFreeDraft,
  },
};

IconData _iconOf(ChatSuggestion suggestion) => switch (suggestion) {
  SummarizeItemSuggestion() => Icons.short_text_rounded,
  QuizMeSuggestion() => Icons.quiz_outlined,
  AskItemSuggestion() => Icons.help_outline_rounded,
  ExploreTopicSuggestion() => Icons.travel_explore_rounded,
  NotebookThemesSuggestion() => Icons.auto_stories_outlined,
  FreeStarterSuggestion(:final starter) => switch (starter) {
    FreeChatStarter.explain => Icons.lightbulb_outline_rounded,
    FreeChatStarter.brainstorm => Icons.tips_and_updates_outlined,
    FreeChatStarter.draft => Icons.edit_note_rounded,
  },
};
