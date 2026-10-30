/// «Explicar» (F43, M15, decisión L): el botón que lleva una pregunta del
/// cuestionario o una tarjeta al chat, en una conversación nueva acotada a
/// sus fuentes y con el modelo elegido. La pieza común del cuestionario, del
/// visor del mazo y de la sesión de Repasar de siempre.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/chat/presentation/providers/chat_handoff.dart';
import 'package:sinapsis/features/creations/presentation/explain_in_chat_question.dart';
import 'package:sinapsis/features/library/domain/repositories/library_repository.dart';
import 'package:sinapsis/features/library/presentation/providers/library_providers.dart';
import 'package:sinapsis/features/reading/domain/extractable_text.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// La fuente de lo que se explica: el título del documento y, si se sabe el
/// tramo, el pasaje.
typedef ExplainSource = ({String title, String passage});

/// Lee la fuente de lo que se explica **al tocar el botón**, no antes: el
/// texto de un documento puede ser un libro, y no se trae entero para cada
/// tarjeta que pasa sin que nadie pida explicarla.
class ExplainSourceReader {
  const ExplainSourceReader({required LibraryRepository Function() library})
    : _library = library;

  final LibraryRepository Function() _library;

  /// El título de [itemId] y, con [start] y [end], su pasaje
  /// ([explainPassage]); `null` si el documento ya no está o no se pudo leer.
  Future<ExplainSource?> read(String itemId, {int? start, int? end}) async {
    final found = await _library().findById(itemId);
    final item = found.getOrElse((_) => null);
    if (item == null) return null;
    final text = start != null && end != null
        ? extractableRendition(item)?.content
        : null;
    return (
      title: item.title,
      passage: text == null ? '' : explainPassage(text, start!, end!),
    );
  }
}

/// Quien lee la fuente de «Explicar».
final explainSourceReaderProvider = Provider<ExplainSourceReader>(
  (ref) =>
      ExplainSourceReader(library: () => ref.read(libraryRepositoryProvider)),
);

/// «Explicar»: un botón con borde y su ícono propio —una chispa sobre un
/// globo de diálogo ([ExplainInChatIcon])— que arma la pregunta con
/// [explainInChatQuestion] y la lleva al chat con [askInChat].
///
/// - [subject] se lee al tocar, así la pregunta dice lo de ese momento: si ya
///   se respondió, qué se eligió.
/// - Con [sourceItemId], la pregunta lleva adentro el título de ese
///   documento y —con [passageStart] y [passageEnd]— el pasaje: así la
///   búsqueda en la bóveda va a él.
/// - Con [notebookId], la conversación nueva queda acotada a ese cuaderno.
///
/// No manda nada sin que se lo toque (decisión L).
class ExplainInChatButton extends ConsumerStatefulWidget {
  const ExplainInChatButton({
    required this.subject,
    this.sourceItemId,
    this.passageStart,
    this.passageEnd,
    this.notebookId,
    super.key,
  });

  final ExplainSubject Function() subject;
  final String? sourceItemId;
  final int? passageStart;
  final int? passageEnd;
  final String? notebookId;

  @override
  ConsumerState<ExplainInChatButton> createState() =>
      _ExplainInChatButtonState();
}

class _ExplainInChatButtonState extends ConsumerState<ExplainInChatButton> {
  /// Mientras se lee la fuente: un segundo toque no abre dos veces el chat.
  var _opening = false;

  Future<void> _explain() async {
    if (_opening) return;
    final l10n = AppLocalizations.of(context)!;
    var subject = widget.subject();
    final itemId = widget.sourceItemId;
    if (itemId != null) {
      setState(() => _opening = true);
      final source = await ref
          .read(explainSourceReaderProvider)
          .read(itemId, start: widget.passageStart, end: widget.passageEnd);
      if (!mounted) return;
      setState(() => _opening = false);
      if (source != null) {
        subject = subject.withSource(
          title: source.title,
          passage: source.passage,
        );
      }
    }
    if (!mounted) return;
    askInChat(
      context,
      ChatHandoff(
        question: explainInChatQuestion(l10n, subject),
        notebookId: widget.notebookId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: l10n.f43S19ExplainTooltip,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: const StadiumBorder(),
          side: BorderSide(color: scheme.outline),
        ),
        onPressed: _opening ? null : () => unawaited(_explain()),
        icon: const ExplainInChatIcon(size: 20),
        label: Text(
          l10n.f43S19Explain,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

/// El ícono de «Explicar»: un globo de diálogo con una chispa de cuatro
/// puntas que asoma por su esquina, y una chispa chiquita encima. El globo
/// toma el color del ícono de alrededor (el del botón) y la chispa, el
/// terciario del tema; el globo se abre donde la chispa lo pisa, así se lee
/// limpio en claro y en oscuro y a cualquier tamaño.
class ExplainInChatIcon extends StatelessWidget {
  const ExplainInChatIcon({this.size = 24, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    final icon = IconTheme.of(context);
    final scheme = Theme.of(context).colorScheme;
    final color = icon.color ?? scheme.onSurface;
    // Deshabilitado, la chispa se apaga con el globo.
    final enabled = (icon.color?.a ?? 1) > 0.6;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          key: const Key('explain-in-chat-icon'),
          painter: ExplainInChatIconPainter(
            bubble: color,
            spark: enabled ? scheme.tertiary : color,
          ),
        ),
      ),
    );
  }
}

/// Lo que dibuja [ExplainInChatIcon], sobre una grilla de 24 × 24.
class ExplainInChatIconPainter extends CustomPainter {
  const ExplainInChatIconPainter({required this.bubble, required this.spark});

  final Color bubble;
  final Color spark;

  /// El centro y el radio de la chispa grande.
  static const _sparkCenter = Offset(17.6, 6.4);
  static const _sparkRadius = 5.6;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width, size.height) / 24;
    // El globo, con su colita abajo a la izquierda.
    final body = Path()
      ..addRRect(
        RRect.fromLTRBR(2.2, 5.2, 19.8, 17.6, const Radius.circular(4.6)),
      );
    final tail = Path()
      ..moveTo(6.2, 17.2)
      ..lineTo(5.2, 21.6)
      ..lineTo(10.8, 17.2)
      ..close();
    final outline = Path.combine(PathOperation.union, body, tail);
    canvas
      ..save()
      ..scale(scale)
      // El globo va en una capa propia: la chispa le abre un hueco antes de
      // dibujarse.
      ..saveLayer(const Rect.fromLTWH(0, 0, 24, 24), Paint())
      ..drawPath(
        outline,
        Paint()
          ..color = bubble
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.9
          ..strokeJoin = StrokeJoin.round,
      )
      // Dos renglones de texto adentro del globo.
      ..drawLine(
        const Offset(6.4, 10.4),
        const Offset(11.2, 10.4),
        Paint()
          ..color = bubble
          ..strokeWidth = 1.7
          ..strokeCap = StrokeCap.round,
      )
      ..drawLine(
        const Offset(6.4, 13.8),
        const Offset(14.6, 13.8),
        Paint()
          ..color = bubble
          ..strokeWidth = 1.7
          ..strokeCap = StrokeCap.round,
      )
      ..drawCircle(
        _sparkCenter,
        _sparkRadius + 1.6,
        Paint()..blendMode = BlendMode.clear,
      )
      ..restore();

    final paint = Paint()..color = spark;
    canvas
      ..drawPath(_sparkle(_sparkCenter, _sparkRadius), paint)
      ..drawPath(_sparkle(const Offset(9.6, 1.9), 1.7), paint)
      ..restore();
  }

  /// Una chispa de cuatro puntas, con los lados curvados hacia adentro.
  static Path _sparkle(Offset c, double r) {
    final k = r * 0.18;
    return Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + k, c.dy - k, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx + k, c.dy + k, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - k, c.dy + k, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx - k, c.dy - k, c.dx, c.dy - r)
      ..close();
  }

  @override
  bool shouldRepaint(ExplainInChatIconPainter oldDelegate) =>
      oldDelegate.bubble != bubble || oldDelegate.spark != spark;
}
