// lib/screens/home/patient/history_tab.dart

import 'package:flutter/material.dart';
import '../../widgets/empty_state.dart';

class HistoryTab extends StatelessWidget {
  const HistoryTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.history_rounded,
      title: 'No history yet',
      message: 'Your dose history will appear here once you start taking medications',
    );
  }
}