import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class ProfileSavedPlaceholderScreen extends StatelessWidget {
  const ProfileSavedPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Text('Household basics saved ✓', style: TextStyle(color: AppColors.textPrimary)),
      ),
    );
  }
}