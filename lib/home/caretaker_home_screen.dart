// lib/screens/home/caretaker_home_screen.dart

import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../widgets/dialogs/confirm_dialog.dart';
import '../widgets/snackbar/app_snackbar.dart';
import '../gui/splash_screen.dart';
import 'caretaker/caretaker_dashboard_tab.dart';
import 'caretaker/patients_tab.dart';
import 'caretaker/alerts_tab.dart';
import 'caretaker/caretaker_profile_tab.dart';

class CaretakerHomeScreen extends StatefulWidget {
  const CaretakerHomeScreen({super.key});

  @override
  State<CaretakerHomeScreen> createState() => _CaretakerHomeScreenState();
}

class _CaretakerHomeScreenState extends State<CaretakerHomeScreen> {
  int _selectedIndex = 0;

  final List<Widget> _tabs = const [
    CaretakerDashboardTab(),
    PatientsTab(),
    AlertsTab(),
    CaretakerProfileTab(),
  ];

  final List<String> _titles = const [
    'Overview',
    'My Patients',
    'Alerts',
    'Profile',
  ];

  Future<void> _handleLogout() async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Sign Out?',
      message: 'You will need to sign in again to check on your patients.',
      confirmText: 'Sign Out',
      type: ConfirmDialogType.warning,
    );

    if (confirmed != true) return;
    if (!mounted) return;

    try {
      await AuthService.instance.signOut();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => const SplashScreen(showBranding: false),
        ),
            (route) => false,
      );
    } catch (e) {
      if (mounted) AppSnackbar.error(context, 'Failed to sign out');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_selectedIndex]),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            onPressed: _handleLogout,
            tooltip: 'Sign Out',
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: _tabs,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primary.withOpacity(0.2),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded, color: AppColors.secondary),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline_rounded),
            selectedIcon: Icon(Icons.people_rounded, color: AppColors.secondary),
            label: 'Patients',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_outlined),
            selectedIcon: Icon(Icons.notifications_rounded, color: AppColors.secondary),
            label: 'Alerts',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person_rounded, color: AppColors.secondary),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}