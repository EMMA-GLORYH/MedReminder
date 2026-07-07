// lib/screens/home/caretaker/patients_tab.dart

import 'package:flutter/material.dart';
import '../../widgets/empty_state.dart';

class PatientsTab extends StatelessWidget {
  const PatientsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.people_outline_rounded,
      title: 'No patients linked yet',
      message: 'Ask a patient to invite you from their app.\n'
          'Once linked, they will appear here.',
    );
  }
}