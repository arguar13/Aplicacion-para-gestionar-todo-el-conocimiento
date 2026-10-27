import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/ai_models/domain/services/model_thinking.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_selection.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_think_more_provider.dart';
import 'package:sinapsis/features/chat/presentation/widgets/chat_scope_sheet.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Si hay una cámara de verdad detrás de `ImageSource.camera` en esta
/// plataforma —el mismo criterio que la tarjeta «Cámara» de la captura—: en
/// Windows, macOS y Linux no hay ninguna, y la tarjeta no se muestra en vez de
/// ofrecer un botón que no hace nada.
bool get chatCameraIsSupported =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// Lo que abre el «+» del campo del chat (F42): todo lo que se le agrega a la
/// pregunta, en un solo lugar.
///
/// - **Cámara · Fotos · Archivos**, en tarjetas: una foto por mensaje, como
///   desde F30 —con una ya adjunta, las dos de fotos se apagan y lo dicen—;
///   «Archivos» trae un documento (o una imagen), que se lee por sus bytes.
/// - **Dónde pregunto**: el modo y el cuaderno, con lo elegido a la vista
///   («Con tu bóveda · Tesis»). Abre la misma hoja que la línea de debajo
///   del modelo (`showChatScopeSheet`): el modo y el alcance se eligen de
///   una sola forma, entre dos entradas —la que está siempre a la vista
///   arriba y la del «+», donde está todo lo que acompaña a la pregunta—.
/// - **Pensar más**: el modelo piensa a fondo antes de contestar, si el que
///   escribe tiene cómo; si no, se ve apagado y dice por qué.
///
/// Los cambios valen en el acto y la hoja se queda abierta; elegir algo para
/// adjuntar la cierra.
class AddToChatSheet extends ConsumerStatefulWidget {
  const AddToChatSheet({
    required this.thinkMore,
    required this.hasImage,
    required this.onCamera,
    required this.onPhotos,
    required this.onFiles,
    required this.onThinkMoreChanged,
    super.key,
  });

  final bool thinkMore;

  /// Si ya hay una foto esperando el mensaje.
  final bool hasImage;
  final VoidCallback onCamera;
  final VoidCallback onPhotos;
  final VoidCallback onFiles;
  final ValueChanged<bool> onThinkMoreChanged;

  @override
  ConsumerState<AddToChatSheet> createState() => _AddToChatSheetState();
}

class _AddToChatSheetState extends ConsumerState<AddToChatSheet> {
  late var _thinkMore = widget.thinkMore;

  void _attach(VoidCallback pick) {
    Navigator.of(context).pop();
    pick();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isFree = ref.watch(chatSelectionProvider.select((s) => s.isFree));
    final scope = watchChatScopeSummary(ref, l10n);
    final thinking = ref.watch(chatThinkMoreSupportProvider);
    final canThink = thinking.support == ThinkMoreSupport.supported;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.chatAddSheetTitle,
              style: theme.textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (chatCameraIsSupported) ...[
                Expanded(
                  child: _AttachCard(
                    key: const Key('chat-add-camera'),
                    icon: Icons.photo_camera_outlined,
                    label: l10n.chatAddCamera,
                    onTap: widget.hasImage
                        ? null
                        : () => _attach(widget.onCamera),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: _AttachCard(
                  key: const Key('chat-add-photos'),
                  icon: Icons.photo_library_outlined,
                  label: l10n.chatAddPhotos,
                  onTap: widget.hasImage
                      ? null
                      : () => _attach(widget.onPhotos),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _AttachCard(
                  key: const Key('chat-add-files'),
                  icon: Icons.attach_file_rounded,
                  label: l10n.chatAddFiles,
                  onTap: () => _attach(widget.onFiles),
                ),
              ),
            ],
          ),
          if (widget.hasImage) ...[
            const SizedBox(height: 8),
            Text(
              l10n.chatAttachOneImage,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Material(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  key: const Key('chat-add-scope'),
                  leading: Icon(
                    isFree ? Icons.chat_bubble_outline : Icons.folder_outlined,
                  ),
                  title: Text(l10n.chatScopeSheetTitle),
                  subtitle: Text(
                    scope,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => unawaited(showChatScopeSheet(context)),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                SwitchListTile(
                  key: const Key('chat-add-think-more'),
                  secondary: const Icon(Icons.psychology_alt_outlined),
                  title: Text(l10n.chatAddThinkMore),
                  subtitle: Text(switch (thinking.support) {
                    ThinkMoreSupport.supported =>
                      l10n.chatAddThinkMoreAvailable,
                    ThinkMoreSupport.onDevice => l10n.chatAddThinkMoreOnDevice,
                    ThinkMoreSupport.notThisModel =>
                      l10n.chatAddThinkMoreNotThisModel(thinking.model),
                  }),
                  value: canThink && _thinkMore,
                  onChanged: canThink
                      ? (on) {
                          setState(() => _thinkMore = on);
                          widget.onThinkMoreChanged(on);
                        }
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Una tarjeta para adjuntar: el ícono grande y el nombre debajo.
class _AttachCard extends StatelessWidget {
  const _AttachCard({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = onTap != null;
    final color = enabled
        ? scheme.onSurface
        : scheme.onSurface.withValues(alpha: 0.38);

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 28,
                  color: enabled
                      ? scheme.primary
                      : scheme.onSurface.withValues(alpha: 0.38),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
