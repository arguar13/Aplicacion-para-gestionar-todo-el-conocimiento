import 'package:cristo_es_el_salvador/features/dashboard/presentation/widgets/dashboard_nav_destination.dart';
import 'package:cristo_es_el_salvador/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

class DashboardNavDrawer extends StatelessWidget {
  const DashboardNavDrawer({
    required this.selectedIndex,
    required this.onSelect,
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return NavigationDrawer(
      selectedIndex: selectedIndex,
      onDestinationSelected: (index) {
        Navigator.of(context).pop();
        onSelect(index);
      },
      children: [
        for (final destination in dashboardNavDestinationsFor(
          AppLocalizations.of(context)!,
        ))
          NavigationDrawerDestination(
            icon: Icon(destination.icon),
            label: Text(destination.label),
          ),
      ],
    );
  }
}
