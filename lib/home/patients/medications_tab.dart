// lib/screens/home/patient/medications_tab.dart

import 'package:flutter/material.dart';
import '../../gui/medications/widgets/medications_list_view.dart';

class MedicationsTab extends StatelessWidget {
  const MedicationsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const MedicationsListView();
  }
}