import 'package:flutter/material.dart';
import 'package:sinapsis/features/dashboard/presentation/widgets/dashboard_nav_destination.dart';
import 'package:sinapsis/l10n/generated/app_localizations.dart';

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
