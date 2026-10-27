import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/design/thumbnail_decode.dart';
import 'package:sinapsis/core/domain/entities/chat_attachment.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Un adjunto ya elegido y guardado, listo para mandarse con el próximo
/// mensaje.
///
/// Guarda los bytes además de [attachment] —que ya tiene su
/// [ChatAttachment.relativePath] en el almacén— para no tener que releerlos
/// del disco al armar el mensaje multimodal ni al dibujar la miniatura en
/// el campo.
@immutable
class PendingChatAttachment {
  const PendingChatAttachment({required this.attachment, required this.bytes});

  final ChatAttachment attachment;
  final Uint8List bytes;

  bool get isImage => attachment.kind == ChatAttachmentKind.image;
}

/// Lo adjunto que espera el próximo mensaje, arriba del texto, dentro de la
/// cápsula del campo (F42): la foto como miniatura y el documento como una
/// ficha con su nombre, cada uno con su ✕ para sacarlo.
class PendingAttachmentsStrip extends StatelessWidget {
  const PendingAttachmentsStrip({
    required this.attachments,
    required this.onRemove,
    super.key,
  });

  final List<PendingChatAttachment> attachments;
  final ValueChanged<PendingChatAttachment> onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final pending in attachments)
            _PendingAttachmentTile(
              key: ValueKey(pending.attachment.relativePath),
              pending: pending,
              onRemove: () => onRemove(pending),
            ),
        ],
      ),
    );
  }
}

/// El lado de la miniatura de una foto que espera mandarse.
const kPendingThumbnailSize = 64.0;

class _PendingAttachmentTile extends StatelessWidget {
  const _PendingAttachmentTile({
    required this.pending,
    required this.onRemove,
    super.key,
  });

  final PendingChatAttachment pending;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = pending.attachment.name;

    final Widget body;
    if (pending.isImage) {
      body = ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.memory(
          pending.bytes,
          width: kPendingThumbnailSize,
          height: kPendingThumbnailSize,
          fit: BoxFit.cover,
          // Una foto adjunta son millones de píxeles: se decodifica al tamaño
          // de la miniatura, no entera.
          cacheWidth: thumbnailDecodeWidth(context, kPendingThumbnailSize),
          semanticLabel: name,
          errorBuilder: (context, error, stackTrace) =>
              const ChatAttachmentPlaceholder(size: kPendingThumbnailSize),
        ),
      );
    } else {
      body = Container(
        constraints: const BoxConstraints(maxWidth: 220),
        padding: const EdgeInsets.fromLTRB(10, 10, 32, 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.description_outlined,
                size: 18,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      );
    }

    return Stack(
      key: const Key('chat-pending-attachment'),
      clipBehavior: Clip.none,
      children: [
        Padding(padding: const EdgeInsets.all(4), child: body),
        // El ✕ se ve chico en la esquina, pero se toca en 48 × 48.
        Positioned(
          top: -12,
          right: -12,
          child: _RemoveBadge(onPressed: onRemove),
        ),
      ],
    );
  }
}

/// El ✕ chiquito en la esquina de un adjunto, con un área de toque de las
/// que no se erran (48 puntos) aunque se vea de 24.
class _RemoveBadge extends StatelessWidget {
  const _RemoveBadge({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: AppLocalizations.of(context)!.chatAttachRemoveTooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      icon: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          shape: BoxShape.circle,
          border: Border.all(color: scheme.surface, width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(Icons.close, size: 14, color: scheme.onInverseSurface),
        ),
      ),
    );
  }
}

/// Un adjunto de un mensaje ya mandado, en la conversación: la foto como
/// miniatura —leída del almacén— y el documento con su nombre.
class ChatAttachmentTile extends ConsumerWidget {
  const ChatAttachmentTile({required this.attachment, super.key});

  final ChatAttachment attachment;

  /// El lado de la miniatura de una foto mandada.
  static const size = 96.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    if (attachment.kind == ChatAttachmentKind.image) {
      final bytesAsync = ref.watch(
        chatAttachmentBytesProvider(attachment.relativePath),
      );
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: bytesAsync.maybeWhen(
          data: (bytes) => bytes == null
              ? const ChatAttachmentPlaceholder(size: size)
              : Image.memory(
                  bytes,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  // Una foto adjunta son millones de píxeles: se decodifica
                  // al tamaño de la miniatura, no entera.
                  cacheWidth: thumbnailDecodeWidth(context, size),
                  semanticLabel: attachment.name,
                  // Bytes corruptos o truncados no deberían tirar abajo el
                  // mensaje entero: un ícono genérico es peor que una
                  // miniatura, pero mucho mejor que una pantalla roja.
                  errorBuilder: (context, error, stackTrace) =>
                      const ChatAttachmentPlaceholder(size: size),
                ),
          orElse: () => const ChatAttachmentPlaceholder(size: size),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.description_outlined, size: 18),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(attachment.name, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

/// Lo que se ve en lugar de una foto que no se puede mostrar.
class ChatAttachmentPlaceholder extends StatelessWidget {
  const ChatAttachmentPlaceholder({required this.size, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      color: scheme.surfaceContainerHigh,
      child: Icon(Icons.image_outlined, color: scheme.onSurfaceVariant),
    );
  }
}
