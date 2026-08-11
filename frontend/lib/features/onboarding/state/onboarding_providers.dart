import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/onboarding_repository.dart';

final onboardingRepositoryProvider = Provider<OnboardingRepository>((ref) => OnboardingRepository());