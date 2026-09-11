import 'package:cristo_es_el_salvador/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

/// Estructura de navegación compartida por `DashboardNavDrawer` (Web/Tablet)
/// y `DashboardBottomNavBar` (móvil), para que ambos muestren siempre los
/// mismos destinos. Son placeholders de navegación: todavía no existen
/// pantallas propias para "Perfil"/"Ajustes", solo la estructura pedida.
class DashboardNavDestination {
  const DashboardNavDestination({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

/// Ya no es una lista `const`: las etiquetas salen de `AppLocalizations`,
/// que necesita el `Locale` activo — no se puede resolver en tiempo de
/// compilación.
List<DashboardNavDestination> dashboardNavDestinationsFor(
  AppLocalizations l10n,
) {
  return [
    DashboardNavDestination(label: l10n.navHome, icon: Icons.home),
    DashboardNavDestination(label: l10n.navProfile, icon: Icons.person),
    DashboardNavDestination(label: l10n.navSettings, icon: Icons.settings),
  ];
}
