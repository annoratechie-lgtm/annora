import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Temporary. Gets replaced when we build the dislikes/exclusions screen next.
class GoalsSavedPlaceholderScreen extends StatelessWidget {
  const GoalsSavedPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Text('Household profile saved ✓', style: TextStyle(color: AppColors.textPrimary)),
      ),
    );
  }
}