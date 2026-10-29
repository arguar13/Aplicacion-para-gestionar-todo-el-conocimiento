import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:sinapsis/features/ai_models/domain/entities/ai_provider.dart';
import 'package:sinapsis/features/ai_models/domain/entities/daily_quota.dart';
import 'package:sinapsis/features/ai_models/domain/services/ai_price_table.dart';
import 'package:sinapsis/features/ai_models/presentation/illustration_texts.dart';
import 'package:sinapsis/features/ai_models/presentation/providers/illustration_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La hoja de la cuota diaria de una cuenta (F43): pedidos, tokens e
/// imágenes por día, o un tope en dólares. Vacío es «sin tope»; sin nada, se
/// vuelve a la estimada de la capa gratuita de [textProvider] (si tiene).
Future<void> showDailyQuotaSheet(
  BuildContext context, {
  required String accountId,
  required String label,
  AiProvider? textProvider,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  builder: (context) => _DailyQuotaSheet(
    accountId: accountId,
    label: label,
    textProvider: textProvider,
  ),
);

class _DailyQuotaSheet extends ConsumerStatefulWidget {
  const _DailyQuotaSheet({
    required this.accountId,
    required this.label,
    this.textProvider,
  });

  final String accountId;
  final String label;
  final AiProvider? textProvider;

  @override
  ConsumerState<_DailyQuotaSheet> createState() => _DailyQuotaSheetState();
}

class _DailyQuotaSheetState extends ConsumerState<_DailyQuotaSheet> {
  late final DailyQuota? _user = ref
      .read(illustrationStoreProvider)
      .userQuotaOf(widget.accountId);
  late final _requests = TextEditingController(
    text: _user?.requests?.toString() ?? '',
  );
  late final _tokens = TextEditingController(
    text: _user?.tokens?.toString() ?? '',
  );
  late final _images = TextEditingController(
    text: _user?.images?.toString() ?? '',
  );
  late final _usd = TextEditingController(text: _usdText(_user?.usd));
  var _invalid = <TextEditingController>{};

  String _usdText(double? usd) {
    if (usd == null) return '';
    return NumberFormat('0.##', 'en').format(usd);
  }

  @override
  void dispose() {
    for (final c in [_requests, _tokens, _images, _usd]) {
      c.dispose();
    }
    super.dispose();
  }

  int? _int(TextEditingController c) {
    final text = c.text.trim().replaceAll('.', '').replaceAll(' ', '');
    if (text.isEmpty) return null;
    final value = int.tryParse(text);
    return value != null && value > 0 ? value : -1;
  }

  double? _double(TextEditingController c) {
    final text = c.text.trim().replaceAll(',', '.');
    if (text.isEmpty) return null;
    final value = double.tryParse(text);
    return value != null && value > 0 ? value : -1;
  }

  Future<void> _save() async {
    final requests = _int(_requests);
    final tokens = _int(_tokens);
    final images = _int(_images);
    final usd = _double(_usd);
    final invalid = {
      if (requests == -1) _requests,
      if (tokens == -1) _tokens,
      if (images == -1) _images,
      if (usd == -1) _usd,
    };
    if (invalid.isNotEmpty) {
      setState(() => _invalid = invalid);
      return;
    }
    await ref
        .read(illustrationActionsProvider)
        .setQuota(
          widget.accountId,
          DailyQuota(
            requests: requests,
            tokens: tokens,
            images: images,
            usd: usd,
          ),
        );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _reset() async {
    await ref
        .read(illustrationActionsProvider)
        .setQuota(widget.accountId, DailyQuota.none);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final provider = widget.textProvider;
    final fallback = provider == null ? null : defaultDailyQuota(provider);
    final fallbackLine = fallback == null
        ? l10n.f43AiQuotaNoDefault
        : l10n.f43AiQuotaDefaultIs(dailyQuotaParts(context, fallback));

    Widget field(
      TextEditingController controller,
      String label,
      IconData icon, {
      required Key key,
      bool decimal = false,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        key: key,
        controller: controller,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        inputFormatters: [
          FilteringTextInputFormatter.allow(
            decimal ? RegExp('[0-9.,]') : RegExp('[0-9]'),
          ),
        ],
        onChanged: (_) {
          if (_invalid.contains(controller)) {
            setState(() => _invalid = {..._invalid}..remove(controller));
          }
        },
        decoration: InputDecoration(
          labelText: label,
          hintText: l10n.f43AiQuotaEmptyMeans,
          prefixIcon: Icon(icon),
          errorText: _invalid.contains(controller)
              ? l10n.f43AiQuotaInvalid
              : null,
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          key: const Key('daily-quota-sheet'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.f43AiQuotaSheetTitle(widget.label),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.f43AiQuotaSheetHint,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              fallbackLine,
              key: const Key('daily-quota-default'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.tertiary,
              ),
            ),
            const SizedBox(height: 18),
            field(
              _requests,
              l10n.f43AiQuotaFieldRequests,
              Icons.forum_outlined,
              key: const Key('daily-quota-requests'),
            ),
            field(
              _tokens,
              l10n.f43AiQuotaFieldTokens,
              Icons.token_outlined,
              key: const Key('daily-quota-tokens'),
            ),
            field(
              _images,
              l10n.f43AiQuotaFieldImages,
              Icons.image_outlined,
              key: const Key('daily-quota-images'),
            ),
            field(
              _usd,
              l10n.f43AiQuotaFieldUsd,
              Icons.attach_money,
              key: const Key('daily-quota-usd'),
              decimal: true,
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const Key('daily-quota-save'),
              onPressed: () => unawaited(_save()),
              icon: const Icon(Icons.check),
              label: Text(l10n.f43AiQuotaSave),
            ),
            if (_user != null) ...[
              const SizedBox(height: 8),
              TextButton(
                key: const Key('daily-quota-reset'),
                onPressed: () => unawaited(_reset()),
                child: Text(l10n.f43AiQuotaReset),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
