import 'package:cristo_es_el_salvador/features/dashboard/presentation/widgets/dashboard_nav_destination.dart';
import 'package:cristo_es_el_salvador/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

class DashboardBottomNavBar extends StatelessWidget {
  const DashboardBottomNavBar({
    required this.selectedIndex,
    required this.onSelect,
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onSelect,
      destinations: [
        for (final destination in dashboardNavDestinationsFor(
          AppLocalizations.of(context)!,
        ))
          NavigationDestination(
            icon: Icon(destination.icon),
            label: destination.label,
          ),
      ],
    );
  }
}
