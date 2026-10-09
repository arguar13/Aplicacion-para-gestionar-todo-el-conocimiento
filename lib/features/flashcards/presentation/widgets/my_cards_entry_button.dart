import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/features/flashcards/domain/entities/study_scope.dart';
import 'package:sinapsis/features/flashcards/presentation/my_cards_route.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// El botón que lleva a «Mis tarjetas» (F31, ola 2, decisión 72): un ícono con
/// su ayuda, para la barra de la sesión de repaso. Con [scope] abre ya
/// recortado (por ejemplo, a las tarjetas de un elemento).
class MyCardsEntryButton extends StatelessWidget {
  const MyCardsEntryButton({this.scope = const StudyScope.all(), super.key});

  final StudyScope scope;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return IconButton(
      key: const Key('my-cards-entry'),
      icon: const Icon(Icons.view_list_outlined),
      tooltip: l10n.myCardsEntryTooltip,
      onPressed: () => context.push(myCardsLocation(scope)),
    );
  }
}
