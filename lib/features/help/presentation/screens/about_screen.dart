import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sinapsis/app/router/route_paths.dart';
import 'package:sinapsis/features/help/presentation/bundled_font_licenses.dart';
import 'package:sinapsis/features/help/presentation/providers/help_providers.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

/// «Acerca de» (F47, paso 7): el nombre, la versión y la compilación de la
/// app que está corriendo, qué es, y las licencias.
///
/// La versión sale del sistema (`package_info_plus`), no de una constante:
/// es la del `pubspec.yaml` con la que se compiló, con el sufijo del sabor
/// en Android —«0.1.0-dev»—, la misma que se ve en Ajustes › Apps.
///
/// Las licencias son la página de Flutter (`showLicensePage`), que ya toma
/// el tema de la app, en claro y en oscuro, con las de los paquetes y las de
/// las letras empaquetadas (ver `registerBundledFontLicenses`).
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final version = ref.watch(appVersionProvider).valueOrNull;
    // El nombre como lo ve el sistema: el del sabor —«Sinapsis Dev»—, el
    // mismo que está debajo del ícono.
    final name = (version?.name.isNotEmpty ?? false) ? version!.name : null;
    final versionLabel = version == null
        ? null
        : l10n.f47P7AboutVersion(version.version, version.build);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.f47P7About)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
        children: [
          const Center(child: _AppMark()),
          const SizedBox(height: 16),
          if (name != null)
            Text(
              name,
              key: const Key('about-name'),
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
          if (versionLabel != null) ...[
            const SizedBox(height: 4),
            Text(
              versionLabel,
              key: const Key('about-version'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            l10n.f47P7AboutDescription,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  key: const Key('about-whats-new'),
                  leading: const Icon(Icons.new_releases_outlined),
                  title: Text(l10n.f47P7WhatsNew),
                  subtitle: Text(l10n.f47P7WhatsNewSubtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(RoutePaths.whatsNew),
                ),
                const Divider(height: 1),
                ListTile(
                  key: const Key('about-licenses'),
                  leading: const Icon(Icons.gavel_outlined),
                  title: Text(l10n.f47P7AboutLicenses),
                  subtitle: Text(l10n.f47P7AboutLicensesSubtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    registerBundledFontLicenses();
                    // Sin nombre todavía, la página usa el título de la app.
                    showLicensePage(
                      context: context,
                      applicationName: name,
                      applicationVersion: versionLabel,
                      applicationIcon: const Padding(
                        padding: EdgeInsets.all(12),
                        child: _AppMark(size: 56),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// La marca de la app: el ícono de las conexiones, en el color de la app.
/// Decorativa: el nombre ya está escrito debajo.
class _AppMark extends StatelessWidget {
  const _AppMark({this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(size * 0.28),
        ),
        child: Icon(
          Icons.hub_outlined,
          size: size * 0.55,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
