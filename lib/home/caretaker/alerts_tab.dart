// lib/screens/home/caretaker/alerts_tab.dart

import 'package:flutter/material.dart';
import '../../widgets/empty_state.dart';

class AlertsTab extends StatelessWidget {
  const AlertsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.notifications_none_rounded,
      title: 'No alerts',
      message: 'You will be notified here when a patient misses a dose',
    );
  }
}