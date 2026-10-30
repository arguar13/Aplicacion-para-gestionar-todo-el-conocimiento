import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/widgets/app_snack_bar.dart';
import 'package:sinapsis/features/transform/domain/services/video_text_notices.dart';
import 'package:sinapsis/features/transform/presentation/providers/transform_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Cuánto queda a la vista el aviso: se lee entero —el nombre del video, en
/// qué estaba y qué se hace— y lleva su ✕ para irse antes.
const kForeignCaptionsNoticeDuration = Duration(seconds: 10);

/// Muestra, esté en la pantalla que esté, el aviso de la red de seguridad del
/// idioma (F45, paso 4): los subtítulos de un video no estaban en el idioma
/// que se habla, no se guardaron, y el texto sale del audio, transcrito en el
/// teléfono con el idioma fijado. Va en el `builder` de `MaterialApp`, como
/// `AiNoticeListener`.
class VideoTextNoticeListener extends ConsumerStatefulWidget {
  const VideoTextNoticeListener({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<VideoTextNoticeListener> createState() =>
      _VideoTextNoticeListenerState();
}

class _VideoTextNoticeListenerState
    extends ConsumerState<VideoTextNoticeListener> {
  StreamSubscription<ForeignCaptionsNotice>? _notices;

  @override
  void initState() {
    super.initState();
    _notices = ref.read(videoTextNoticeBusProvider).notices.listen(_show);
  }

  @override
  void dispose() {
    unawaited(_notices?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;

  void _show(ForeignCaptionsNotice notice) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final l10n = AppLocalizations.of(context);
    if (messenger == null || l10n == null) return;
    messenger.showSnackBar(
      AppSnackBar(
        key: const Key('foreign-captions-notice'),
        duration: kForeignCaptionsNoticeDuration,
        content: Text(foreignCaptionsMessage(l10n, notice)),
      ),
    );
  }
}

/// Lo que dice el aviso de [notice].
String foreignCaptionsMessage(
  AppLocalizations l10n,
  ForeignCaptionsNotice notice,
) {
  final found = l10n.f45S4LanguageName(notice.foundLanguage ?? '');
  final spoken = l10n.f45S4LanguageName(notice.audioLanguage);
  return notice.transcribing
      ? l10n.f45S4ForeignCaptionsAudio(notice.title, found, spoken)
      : l10n.f45S4ForeignCaptionsNoAudio(notice.title, found, spoken);
}
