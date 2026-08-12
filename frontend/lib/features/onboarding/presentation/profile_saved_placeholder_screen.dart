import 'package:flutter/material.dart';

import '../../home/presentation/home_screen.dart';

/// Temporary completion route kept under onboarding while the home feature
/// is being introduced. The actual post-onboarding destination is HomeScreen.
class ProfileSavedPlaceholderScreen extends StatelessWidget {
  const ProfileSavedPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const HomeScreen();
  }
}
