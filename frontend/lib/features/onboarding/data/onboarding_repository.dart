import 'package:supabase_flutter/supabase_flutter.dart';

class OnboardingProfile {
  final int familySize;
  final double monthlyBudget;
  final String dietaryPreference;
  final List<String> dietaryGoals;
  final bool onboardingCompleted;

  OnboardingProfile({
    required this.familySize,
    required this.monthlyBudget,
    required this.dietaryPreference,
    required this.dietaryGoals,
    required this.onboardingCompleted,
  });

  factory OnboardingProfile.fromMap(Map<String, dynamic> map) => OnboardingProfile(
        familySize: map['family_size'] as int,
        monthlyBudget: (map['monthly_budget'] as num).toDouble(),
        dietaryPreference: map['dietary_preference'] as String,
        dietaryGoals: (map['dietary_goals'] as List<dynamic>? ?? []).cast<String>(),
        onboardingCompleted: map['onboarding_completed'] as bool,
      );
}

/// Talks directly to Supabase for onboarding reads/writes -- see
/// docs/architecture.md for why onboarding doesn't go through FastAPI.
class OnboardingRepository {
  final SupabaseClient _client = Supabase.instance.client;

  String get _userId => _client.auth.currentUser!.id;

  Future<OnboardingProfile?> fetchProfile() async {
    final row = await _client
        .from('onboarding_profiles')
        .select()
        .eq('user_id', _userId)
        .maybeSingle();
    if (row == null) return null;
    return OnboardingProfile.fromMap(row);
  }

  /// Updates, not inserts -- the handle_new_user trigger already created
  /// this row (with placeholder values) when the account was created.
  /// dietaryGoals may be an empty list -- it's optional and skippable.
  Future<void> saveHouseholdBasics({
    required int familySize,
    required double monthlyBudget,
    required String dietaryPreference,
    required List<String> dietaryGoals,
  }) {
    return _client.from('onboarding_profiles').update({
      'family_size': familySize,
      'monthly_budget': monthlyBudget,
      'dietary_preference': dietaryPreference,
      'dietary_goals': dietaryGoals,
    }).eq('user_id', _userId);
  }

  /// Saves the final onboarding preferences, replaces dietary exclusions,
  /// and marks the onboarding profile as complete.
  Future<void> completeOnboarding({
    required List<String> dietaryGoals,
    required List<String> exclusions,
  }) async {
    final cleanedExclusions = <String>[];
    final seen = <String>{};

    for (final exclusion in exclusions) {
      final value = exclusion.trim();
      if (value.isNotEmpty && seen.add(value.toLowerCase())) {
        cleanedExclusions.add(value);
      }
    }

    await _client
        .from('dietary_exclusions')
        .delete()
        .eq('user_id', _userId);

    if (cleanedExclusions.isNotEmpty) {
      await _client.from('dietary_exclusions').insert(
        cleanedExclusions
            .map(
              (ingredient) => {
                'user_id': _userId,
                'ingredient_name': ingredient,
              },
            )
            .toList(),
      );
    }

    await _client
        .from('onboarding_profiles')
        .update({
          'dietary_goals': dietaryGoals,
          'onboarding_completed': true,
          'onboarding_completed_at':
              DateTime.now().toUtc().toIso8601String(),
        })
        .eq('user_id', _userId);
  }
}
