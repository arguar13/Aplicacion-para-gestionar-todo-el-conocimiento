import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/core/design/theme_mode_notifier.dart'
    show sharedPreferencesProvider;
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/presentation/ai_model_texts.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/ai_models_providers.dart';
import 'package:sinapsis/features/ai_models/presentation/widgets/ai_account_switcher.dart';
import 'package:sinapsis/features/chat/domain/entities/chat_model_option.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_model_option_notifier.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Si ya se mostró el aviso de qué sale del teléfono para [provider].
String aiPrivacySeenKey(AiProvider provider) =>
    'ai_cloud_privacy_seen_${provider.storageKey}';

/// Los proveedores que se ofrecen, en el orden en que se muestran: Gemini y
/// Gemma siempre; OpenAI y Claude, si esta versión de la app sabe hablarles.
List<AiProvider> offeredAiProviders(Map<AiProvider, Object> wires) => [
  AiProvider.gemini,
  AiProvider.gemma,
  for (final p in [AiProvider.openAi, AiProvider.anthropic])
    if (wires.containsKey(p)) p,
];

/// El nombre de una opción de Gemma, como lo ve la persona.
String gemmaOptionTitle(AppLocalizations l10n, ChatModelOption option) =>
    switch (option) {
      ChatModelOption.gemma4E4b => l10n.chatModelOptionGemma4Title,
      ChatModelOption.gemma3nE4b => l10n.chatModelOptionGemma3nTitle,
      ChatModelOption.gemma412b => l10n.chatModelOptionGemma412bTitle,
    };

/// El modelo que escribe ahora, con su nombre para mostrar (F32, F42): el
/// elegido en la nube —o el recomendado del proveedor— o la opción de Gemma.
/// Lo muestran la pantalla del modelo y la píldora del chat; se redibuja al
/// cambiar lo elegido o la lista de modelos.
///
/// Si el proveedor todavía no dijo cuál recomienda y no se eligió ninguno,
/// [unknown] —por defecto, el nombre del proveedor—.
String watchChosenModelTitle(
  WidgetRef ref,
  AppLocalizations l10n, {
  String? unknown,
}) {
  final settings = ref.watch(aiModelSettingsProvider);
  final provider = settings.provider;
  if (!provider.isCloud) {
    return gemmaOptionTitle(l10n, ref.watch(chatModelOptionNotifierProvider));
  }
  final models = ref.watch(cloudModelsProvider(provider));
  final id =
      settings.modelOf(provider) ??
      ref.watch(cloudModelCatalogProvider).recommended(provider);
  if (id == null) return unknown ?? provider.label(l10n);
  return models.where((m) => m.id == id).firstOrNull?.displayName ?? id;
}

/// Si la persona ya sabe qué sale del teléfono con [provider]: la primera vez
/// —al elegirlo o al cargar su primera clave, porque Gemini viene elegido de
/// fábrica— se le explica y tiene que aceptarlo. `false` si no aceptó.
Future<bool> ensureAiPrivacyAccepted(
  BuildContext context,
  WidgetRef ref,
  AiProvider provider,
) async {
  if (!provider.isCloud) return true;
  final prefs = ref.read(sharedPreferencesProvider);
  if (prefs.getBool(aiPrivacySeenKey(provider)) ?? false) return true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AiPrivacyDialog(provider: provider),
  );
  if (ok != true) return false;
  await prefs.setBool(aiPrivacySeenKey(provider), true);
  return true;
}

/// Qué sale del teléfono con un proveedor en la nube, antes de elegirlo.
class AiPrivacyDialog extends StatelessWidget {
  const AiPrivacyDialog({required this.provider, super.key});

  final AiProvider provider;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return AlertDialog(
      icon: Icon(Icons.shield_outlined, color: theme.colorScheme.primary),
      title: Text(l10n.lmPrivacyTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.lmPrivacyBody),
          const SizedBox(height: 12),
          Text(
            provider.hasFreeTier ? l10n.lmPrivacyFreeTier : l10n.lmPrivacyPaid,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('lm-privacy-continue'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.lmPrivacyContinue(provider.label(l10n))),
        ),
      ],
    );
  }
}

/// La hoja para elegir quién contesta (F42): el proveedor, el modelo y la
/// cuenta, sin salir de donde se está. Es lo que hacían en el chat el robot
/// —abría la pantalla del modelo— y el círculo de la cuenta; lo que no entra
/// acá —cargar claves, la cuota, bajar Gemma— sigue en la pantalla del
/// modelo, a un toque.
///
/// [onOpenRoute] abre una pantalla (la del modelo, la de Gemma) después de
/// cerrar la hoja: quien la abre decide qué hacer al volver.
Future<void> showAiModelPicker(
  BuildContext context, {
  required ValueChanged<String> onOpenRoute,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) => AiModelPicker(
      onOpenRoute: (route) {
        Navigator.of(sheetContext).pop();
        onOpenRoute(route);
      },
    ),
  );
}

/// El contenido de [showAiModelPicker].
class AiModelPicker extends ConsumerWidget {
  const AiModelPicker({required this.onOpenRoute, super.key});

  final ValueChanged<String> onOpenRoute;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final provider = ref.watch(
      aiModelSettingsProvider.select((s) => s.provider),
    );
    final offered = offeredAiProviders(ref.watch(cloudWiresProvider));

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.aiPickerTitle,
                style: theme.textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.aiPickerHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in offered)
                  ChoiceChip(
                    key: Key('ai-picker-provider-${p.storageKey}'),
                    avatar: Icon(p.icon, size: 18),
                    label: Text(p.label(l10n)),
                    selected: p == provider,
                    showCheckmark: false,
                    onSelected: p == provider
                        ? null
                        : (_) => unawaited(_chooseProvider(context, ref, p)),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            _PickerLabel(l10n.aiPickerModel),
            if (provider.isCloud)
              _CloudModels(provider: provider)
            else
              _GemmaModel(onManage: () => onOpenRoute(RoutePaths.chatModel)),
            if (provider.isCloud) ...[
              const SizedBox(height: 20),
              _PickerLabel(l10n.aiPickerAccount),
              _Account(
                provider: provider,
                onAddKey: () => onOpenRoute(RoutePaths.languageModel),
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const Key('ai-picker-more'),
                onPressed: () => onOpenRoute(RoutePaths.languageModel),
                icon: const Icon(Icons.tune),
                label: Text(l10n.aiPickerMore),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _chooseProvider(
    BuildContext context,
    WidgetRef ref,
    AiProvider provider,
  ) async {
    if (!await ensureAiPrivacyAccepted(context, ref, provider)) return;
    await ref.read(aiModelSettingsProvider.notifier).chooseProvider(provider);
  }
}

class _PickerLabel extends StatelessWidget {
  const _PickerLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Un grupo de opciones con el mismo contenedor que las tarjetas de Ajustes.
class _OptionsCard extends StatelessWidget {
  const _OptionsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Una opción elegible: la elegida lleva el tilde y se anuncia como tal.
class _Option extends StatelessWidget {
  const _Option({
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    super.key,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: ListTile(
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        selected: selected,
        trailing: selected ? Icon(Icons.check, color: scheme.primary) : null,
        onTap: selected ? null : onTap,
      ),
    );
  }
}

class _CloudModels extends ConsumerWidget {
  const _CloudModels({required this.provider});

  final AiProvider provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final models = ref.watch(cloudModelsProvider(provider));
    final chosen = ref.watch(
      aiModelSettingsProvider.select((s) => s.modelOf(provider)),
    );
    final recommended = ref
        .watch(cloudModelCatalogProvider)
        .recommended(provider);
    String nameOf(String id) =>
        models.where((m) => m.id == id).firstOrNull?.displayName ?? id;
    final ids = {
      for (final m in models) m.id,
      // Lo elegido aunque la lista ya no lo traiga: que se vea qué se usa.
      ?chosen,
    };
    void choose(String? id) => unawaited(
      ref.read(aiModelSettingsProvider.notifier).chooseModel(provider, id),
    );

    return _OptionsCard(
      children: [
        _Option(
          key: const Key('ai-picker-model-recommended'),
          title: recommended == null
              ? l10n.lmModelRecommendedPlain
              : l10n.lmModelRecommended(nameOf(recommended)),
          selected: chosen == null,
          onTap: () => choose(null),
        ),
        for (final id in ids)
          _Option(
            key: Key('ai-picker-model-$id'),
            title: nameOf(id),
            selected: chosen == id,
            onTap: () => choose(id),
          ),
      ],
    );
  }
}

class _GemmaModel extends ConsumerWidget {
  const _GemmaModel({required this.onManage});

  final VoidCallback onManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final option = ref.watch(chatModelOptionNotifierProvider);
    return _OptionsCard(
      children: [
        _Option(
          title: gemmaOptionTitle(l10n, option),
          subtitle: l10n.lmBadgeLocal,
          selected: true,
          onTap: null,
        ),
        ListTile(
          key: const Key('ai-picker-gemma-manage'),
          leading: const Icon(Icons.download_for_offline_outlined),
          title: Text(l10n.lmGemmaManage),
          trailing: const Icon(Icons.chevron_right),
          onTap: onManage,
        ),
      ],
    );
  }
}

class _Account extends ConsumerWidget {
  const _Account({required this.provider, required this.onAddKey});

  final AiProvider provider;
  final VoidCallback onAddKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final hasAccounts = ref.watch(aiAccountsViewProvider).accounts.isNotEmpty;
    if (hasAccounts) {
      // El mismo menú de cuentas de la pantalla del modelo (F32).
      return const Align(
        alignment: AlignmentDirectional.centerStart,
        child: AiAccountSwitcher(),
      );
    }
    return _OptionsCard(
      children: [
        ListTile(
          key: const Key('ai-picker-add-key'),
          leading: const Icon(Icons.key_outlined),
          title: Text(l10n.lmStatusNeedsAccount(provider.label(l10n))),
          subtitle: Text(l10n.lmAddAccount),
          trailing: const Icon(Icons.chevron_right),
          onTap: onAddKey,
        ),
      ],
    );
  }
}
