import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/features/narration/presentation/read_aloud/read_aloud_controller.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo que se lee en voz alta que cae en el tramo `[from, to)` del texto
/// `sourceKey`, con las posiciones contadas desde `from`; `null` si lo que
/// suena no es de ahí.
///
/// Para una pantalla que muestra un texto largo de a pedazos —el libro, de a
/// páginas—: cada página pregunta solo por lo suyo, y se vuelve a construir
/// cuando lo que suena entra, sale o se mueve dentro de ella, no con cada
/// línea del libro entero.
final readAloudSpanProvider = Provider.autoDispose
    .family<(int, int)?, ({String sourceKey, int from, int to})>((ref, key) {
      final reading = ref.watch(readAloudHighlightProvider(key.sourceKey));
      if (reading == null) return null;
      final (start, end) = reading;
      if (end <= key.from || start >= key.to) return null;
      return (
        math.max(start, key.from) - key.from,
        math.min(end, key.to) - key.from,
      );
    });

/// En qué parte de la vista se lee cómodo lo que suena, como fracciones de su
/// alto contadas desde arriba: un visor que sigue la lectura no se mueve
/// mientras la línea esté entre [top] y [bottom], y cuando sale, la lleva a
/// [landing].
///
/// Abajo queda lugar de sobra: el reproductor abierto tapa el último tercio de
/// la pantalla. Llevar la línea cerca de arriba hace que la vista se mueva de
/// a mucho y pocas veces, como dar vuelta una página, y no un renglón con
/// cada renglón.
abstract final class ReadAloudBand {
  static const top = 0.05;
  static const bottom = 0.7;
  static const landing = 0.2;

  /// Si [line] está dentro de la franja cómoda de [view] —los dos en las
  /// mismas coordenadas—, de lado a lado incluido.
  static bool contains(Rect view, Rect line) =>
      line.top >= view.top + view.height * top &&
      line.bottom <= view.top + view.height * bottom &&
      line.left >= view.left &&
      line.right <= view.right;

  /// Dónde va el centro de [view] para que [line] quede a la altura de
  /// [landing]. De lado a lado no se mueve si la línea ya entra; si no —con
  /// zoom—, se la centra.
  static Offset centerFor(Rect view, Rect line) {
    final fits = line.left >= view.left && line.right <= view.right;
    return Offset(
      fits ? view.center.dx : line.center.dx,
      line.top - view.height * landing + view.height / 2,
    );
  }
}

/// Si un visor sigue lo que se lee en voz alta —da vuelta la página, se
/// desplaza hasta la línea— o lo dejó de seguir porque la persona se movió.
///
/// La política es la de un lector de libros con voz: el visor sigue la
/// lectura mientras la persona no lo mueva. Si desplaza o pasa de página a
/// mano, el visor la deja tranquila —no pelea con ella para volver— y ofrece
/// «Volver a la lectura» (ver [ReadAloudBackToReading]). Vuelve a seguir al
/// tocarlo, cuando lo que suena entra por sí solo en lo que la persona está
/// mirando y cuando empieza otra lectura —ver [resumeOnNewReadings]—.
class ReadAloudFollow extends ChangeNotifier {
  var _following = true;

  bool get following => _following;

  /// La persona movió la vista: no seguir.
  void release() {
    if (!_following) return;
    _following = false;
    notifyListeners();
  }

  /// Volver a seguir.
  void resume() {
    if (_following) return;
    _following = true;
    notifyListeners();
  }

  /// Lo que suena cambió de lugar, y [comfortable] dice si se lee cómodo en
  /// lo que se ve (ver [ReadAloudBand]): si el visor tiene que llevar la vista
  /// hasta ahí. Siguiendo, solo si salió de la franja. Sin seguir, nunca: y si
  /// llegó sola a la franja —la persona está mirando justo eso—, vuelve a
  /// seguirla.
  bool shouldMoveTo({required bool comfortable}) {
    if (!_following) {
      if (comfortable) resume();
      return false;
    }
    return !comfortable;
  }

  /// Vuelve a seguir cada vez que empieza otra lectura —otro documento, otra
  /// parte de él—: quien la empezó quiere verla. Se llama en `build`.
  void resumeOnNewReadings(WidgetRef ref) => ref.listen(
    readAloudControllerProvider.select((s) => (s.document?.id, s.scope)),
    (previous, next) {
      if (previous != next) resume();
    },
  );
}

/// «Volver a la lectura»: la pastilla que aparece arriba de un visor cuando
/// la persona se alejó de lo que se lee en voz alta del texto [sourceKey]
/// —ver [ReadAloudFollow]—. Tocarla llama a [onPressed], que lleva la vista
/// hasta ahí y vuelve a seguir.
///
/// Escondida no ocupa lugar ni recibe toques. Aparece y se va deslizándose,
/// sin animación si la persona las apagó en el sistema.
class ReadAloudBackToReading extends ConsumerWidget {
  const ReadAloudBackToReading({
    required this.sourceKey,
    required this.follow,
    required this.onPressed,
    super.key,
  });

  final String sourceKey;
  final ReadAloudFollow follow;
  final VoidCallback onPressed;

  static const _move = Duration(milliseconds: 220);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reading = ref.watch(
      readAloudHighlightProvider(sourceKey).select((range) => range != null),
    );
    final still = MediaQuery.disableAnimationsOf(context);
    return ListenableBuilder(
      listenable: follow,
      builder: (context, child) {
        final visible = reading && !follow.following;
        return IgnorePointer(
          ignoring: !visible,
          child: AnimatedSlide(
            offset: visible ? Offset.zero : const Offset(0, -0.6),
            duration: still ? Duration.zero : _move,
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: still ? Duration.zero : _move,
              curve: Curves.easeOutCubic,
              child: ExcludeSemantics(excluding: !visible, child: child),
            ),
          ),
        );
      },
      child: _Pill(onPressed: onPressed),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: l10n.readAloudBackToReadingHint,
      child: Material(
        key: const Key('read-aloud-back-to-reading'),
        color: scheme.inverseSurface,
        elevation: 3,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 18, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.record_voice_over_rounded,
                  size: 18,
                  color: scheme.onInverseSurface,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.readAloudBackToReading,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: scheme.onInverseSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
