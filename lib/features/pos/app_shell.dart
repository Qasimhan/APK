import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../settings/settings_screen.dart';

/// Bottom-nav shell hosting the three main tabs. POS and Inventory are
/// implemented in the mobile app; Settings remains a placeholder for Phase 9.
class AppShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const AppShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.point_of_sale_outlined),
            selectedIcon: Icon(Icons.point_of_sale),
            label: 'POS',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Inventory',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class PosTabPlaceholder extends StatelessWidget {
  const PosTabPlaceholder({super.key});
  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('POS — built in Phase 4/5'));
}

class InventoryTabPlaceholder extends StatelessWidget {
  const InventoryTabPlaceholder({super.key});
  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('Inventory — built in Phase 6'));
}

class SettingsTabPlaceholder extends StatelessWidget {
  const SettingsTabPlaceholder({super.key});
  @override
  Widget build(BuildContext context) => const SettingsScreen();
}
