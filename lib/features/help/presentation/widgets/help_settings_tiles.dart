import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// Lo que hay en Ajustes › Ayuda (F47, paso 7), en el orden en que se ve: de
/// lo que más se busca a lo que menos.
enum HelpPage {
  guide(RoutePaths.userGuide, Icons.menu_book_outlined);

  const HelpPage(this.route, this.icon);

  final String route;
  final IconData icon;

  String title(AppLocalizations l10n) => switch (this) {
    HelpPage.guide => l10n.f47P7Guide,
  };

  String subtitle(AppLocalizations l10n) => switch (this) {
    HelpPage.guide => l10n.f47P7GuideSubtitle,
  };
}

/// La fila de Ajustes que abre [page].
class HelpSettingsTile extends StatelessWidget {
  const HelpSettingsTile(this.page, {super.key});

  final HelpPage page;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListTile(
      key: Key('settings-help-${page.name}'),
      leading: Icon(page.icon),
      title: Text(page.title(l10n)),
      subtitle: Text(page.subtitle(l10n)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(page.route),
    );
  }
}
