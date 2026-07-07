// lib/screens/home/patient_home_screen.dart

import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/dialogs/confirm_dialog.dart';
import '../widgets/snackbar/app_snackbar.dart';
import '../auth/login_screen.dart';
import 'patients/dashboard_tab.dart';
import 'patients/medications_tab.dart';
import 'patients/history_tab.dart';
import 'patients/profile_tab.dart';

class PatientHomeScreen extends StatefulWidget {
  const PatientHomeScreen({super.key});

  @override
  State<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

class _PatientHomeScreenState extends State<PatientHomeScreen> {
  int _selectedIndex = 0;
  bool _sidebarOpen = false;

  static const _titles = ['Dashboard', 'Medications', 'History', 'Profile'];

  void _selectTab(int index) {
    setState(() {
      _selectedIndex = index;
      _sidebarOpen = false;
    });
  }

  void _openSidebar() => setState(() => _sidebarOpen = true);
  void _closeSidebar() => setState(() => _sidebarOpen = false);

  Future<void> _handleLogout() async {
    _closeSidebar();

    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Sign Out?',
      message: 'You will need to sign in again to access your medications.',
      confirmText: 'Sign Out',
      type: ConfirmDialogType.danger,
    );

    if (confirmed != true || !mounted) return;

    try {
      await AuthService.instance.signOut();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
      );
    } catch (_) {
      if (mounted) AppSnackbar.error(context, 'Failed to sign out');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <Widget>[
      DashboardTab(onNavigateToTab: _selectTab),
      const MedicationsTab(),
      const HistoryTab(),
      const ProfileTab(),
    ];

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                PatientTopBar(
                  title: _titles[_selectedIndex],
                  isDashboard: _selectedIndex == 0,
                  onMenuTap: _openSidebar,
                ),
                Expanded(
                  child: IndexedStack(
                    index: _selectedIndex,
                    children: tabs,
                  ),
                ),
              ],
            ),
            if (_sidebarOpen)
              GestureDetector(
                onTap: _closeSidebar,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  color: Colors.black.withValues(alpha: 0.5),
                ),
              ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              top: 0,
              bottom: 0,
              left: _sidebarOpen ? 0 : -260,
              width: 260,
              child: PatientSidebar(
                selectedIndex: _selectedIndex,
                onDestinationSelected: _selectTab,
                onLogout: _handleLogout,
                onClose: _closeSidebar,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// TOP BAR - Full width, lime green menu button
// ══════════════════════════════════════════════════════════════
class PatientTopBar extends StatelessWidget {
  final String title;
  final bool isDashboard;
  final VoidCallback onMenuTap;

  const PatientTopBar({
    super.key,
    required this.title,
    required this.isDashboard,
    required this.onMenuTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDashboard ? AppColors.secondary : AppColors.surface,
        border: !isDashboard
            ? Border(bottom: BorderSide(color: AppColors.border))
            : null,
      ),
      child: Row(
        children: [
          Material(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: onMenuTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(
                  Icons.menu_rounded,
                  color: AppColors.secondary,
                  size: 22,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: AppTextStyles.h2.copyWith(
                color: isDashboard ? Colors.white : AppColors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// SIDEBAR
// ══════════════════════════════════════════════════════════════
class PatientSidebar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onLogout;
  final VoidCallback onClose;

  const PatientSidebar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.onLogout,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.secondary,
      elevation: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SidebarHeader(onClose: onClose),
          const SizedBox(height: 8),
          const _SidebarDivider(),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: [
                  _SidebarItem(
                    icon: Icons.dashboard_outlined,
                    activeIcon: Icons.dashboard_rounded,
                    label: 'Dashboard',
                    selected: selectedIndex == 0,
                    onTap: () => onDestinationSelected(0),
                  ),
                  _SidebarItem(
                    icon: Icons.medication_outlined,
                    activeIcon: Icons.medication_rounded,
                    label: 'Medications',
                    selected: selectedIndex == 1,
                    onTap: () => onDestinationSelected(1),
                  ),
                  _SidebarItem(
                    icon: Icons.history_outlined,
                    activeIcon: Icons.history_rounded,
                    label: 'History',
                    selected: selectedIndex == 2,
                    onTap: () => onDestinationSelected(2),
                  ),
                  _SidebarItem(
                    icon: Icons.person_outline,
                    activeIcon: Icons.person_rounded,
                    label: 'Profile',
                    selected: selectedIndex == 3,
                    onTap: () => onDestinationSelected(3),
                  ),
                ],
              ),
            ),
          ),
          const _SidebarDivider(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: _LogoutTile(onTap: onLogout),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// HEADER
// ══════════════════════════════════════════════════════════════
class _SidebarHeader extends StatelessWidget {
  final VoidCallback onClose;
  const _SidebarHeader({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 12, 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.medication_rounded,
              color: AppColors.secondary,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MedReminder',
                  style: AppTextStyles.titleMedium.copyWith(
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Patient',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          Material(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: onClose,
              borderRadius: BorderRadius.circular(10),
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(
                  Icons.close_rounded,
                  color: Colors.white70,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// DIVIDER
// ══════════════════════════════════════════════════════════════
class _SidebarDivider extends StatelessWidget {
  const _SidebarDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 1,
        color: Colors.white.withValues(alpha: 0.1),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// ITEM
// ══════════════════════════════════════════════════════════════
class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.2)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: selected
                  ? Border.all(
                color: AppColors.primary.withValues(alpha: 0.4),
              )
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  selected ? activeIcon : icon,
                  color: selected ? AppColors.primary : Colors.white70,
                  size: 22,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: selected ? AppColors.primary : Colors.white70,
                      fontWeight:
                      selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (selected)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// LOGOUT TILE
// ══════════════════════════════════════════════════════════════
class _LogoutTile extends StatelessWidget {
  final VoidCallback onTap;
  const _LogoutTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.error.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: AppColors.error,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.power_settings_new_rounded,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Sign out',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}