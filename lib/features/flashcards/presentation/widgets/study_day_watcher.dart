import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sinapsis/core/util/util_providers.dart';
import 'package:sinapsis/features/flashcards/domain/services/study_day.dart';
import 'package:sinapsis/features/flashcards/presentation/providers/study_providers.dart';

/// Avisa cuando empieza un día de estudio nuevo (F31): a las 4:00, los límites
/// vuelven a empezar y lo pospuesto hasta mañana vuelve, sin que nada se
/// escriba en la base. Sin esto, la insignia de Repasar de una app que quedó
/// abierta toda la noche seguiría mostrando la cuenta de ayer.
///
/// Es un widget y no un temporizador del repositorio a propósito: el
/// temporizador vive y muere con el widget (se cancela en `dispose`), en vez
/// de sobrevivir a la pantalla que lo pidió. Se monta una vez, alrededor de la
/// aplicación; actualiza [studyDayStartProvider], de la que dependen los
/// conteos.
class StudyDayWatcher extends ConsumerStatefulWidget {
  const StudyDayWatcher({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<StudyDayWatcher> createState() => _StudyDayWatcherState();
}

class _StudyDayWatcherState extends ConsumerState<StudyDayWatcher> {
  static const _day = StudyDay();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  /// Un segundo después del cambio de día, para caer del lado nuevo.
  void _schedule() {
    final now = ref.read(clockProvider)();
    final wait = _day.endOf(now).difference(now) + const Duration(seconds: 1);
    _timer = Timer(wait, () {
      if (!mounted) return;
      ref.read(studyDayStartProvider.notifier).state = _day.startOf(
        ref.read(clockProvider)(),
      );
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
