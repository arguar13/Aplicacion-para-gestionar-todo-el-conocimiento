import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sinapsis/features/creations/presentation/kinds/creation_kind_spec.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El ícono de un tipo de creación con su color propio, sobre un cuadrado
/// redondeado apenas teñido de ese color: el de las filas de «Lo creado», las
/// hojas y los visores.
class CreationKindIcon extends StatelessWidget {
  const CreationKindIcon({required this.spec, this.size = 40, super.key});

  final CreationKindSpec spec;
  final double size;

  @override
  Widget build(BuildContext context) {
    final accent = spec.accent.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      alignment: Alignment.center,
      child: Icon(spec.iconData, size: size * 0.55, color: accent),
    );
  }
}

/// Cuándo se creó, como en las capturas: «Recién», «Hace 12 min», «Hace 3
/// horas», «Hace 4 días»; pasada una semana, la fecha.
String creationAgo(
  AppLocalizations l10n,
  DateTime then,
  DateTime now, {
  required String locale,
}) {
  final elapsed = now.difference(then);
  if (elapsed.inMinutes < 1) return l10n.f43StudioAgoNow;
  if (elapsed.inHours < 1) return l10n.f43StudioAgoMinutes(elapsed.inMinutes);
  if (elapsed.inDays < 1) return l10n.f43StudioAgoHours(elapsed.inHours);
  if (elapsed.inDays < 7) return l10n.f43StudioAgoDays(elapsed.inDays);
  return DateFormat.yMMMd(locale).format(then.toLocal());
}
