import 'package:supabase_flutter/supabase_flutter.dart';

class OnboardingProfile {
  final int familySize;
  final double monthlyBudget;
  final String dietaryPreference;
  final bool onboardingCompleted;

  OnboardingProfile({
    required this.familySize,
    required this.monthlyBudget,
    required this.dietaryPreference,
    required this.onboardingCompleted,
  });

  factory OnboardingProfile.fromMap(Map<String, dynamic> map) =>
      OnboardingProfile(
        familySize: map['family_size'] as int,
        monthlyBudget: (map['monthly_budget'] as num).toDouble(),
        dietaryPreference: map['dietary_preference'] as String,
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

  /// Upsert rather than only update: the database trigger normally creates a
  /// profile at sign-up, but this also recovers safely if a user account was
  /// created before that trigger was deployed.
  Future<void> saveHouseholdBasics({
    required int familySize,
    required double monthlyBudget,
    required String dietaryPreference,
  }) async {
    await _client
        .from('onboarding_profiles')
        .upsert(
          {
            'user_id': _userId,
            'family_size': familySize,
            'monthly_budget': monthlyBudget,
            'dietary_preference': dietaryPreference,
          },
          onConflict: 'user_id',
        )
        .select('user_id')
        .single();
  }

  /// Saves the optional preferences from the final onboarding step and marks
  /// the profile complete. Exclusions are replaced so this remains safe if a
  /// user revisits the step before the app has a Settings screen.
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

    await _client.from('dietary_exclusions').delete().eq('user_id', _userId);
    if (cleanedExclusions.isNotEmpty) {
      await _client.from('dietary_exclusions').insert(
            cleanedExclusions
                .map((ingredient) => {
                      'user_id': _userId,
                      'ingredient_name': ingredient,
                    })
                .toList(),
          );
    }

    await _client
        .from('onboarding_profiles')
        .update({
          'dietary_goals': dietaryGoals,
          'onboarding_completed': true,
          'onboarding_completed_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('user_id', _userId)
        .select('user_id')
        .single();
  }
}
