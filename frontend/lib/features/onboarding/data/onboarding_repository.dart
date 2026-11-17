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

  factory OnboardingProfile.fromMap(Map<String, dynamic> map) =>
      OnboardingProfile(
        familySize: map['family_size'] as int,
        monthlyBudget: (map['monthly_budget'] as num).toDouble(),
        dietaryPreference: map['dietary_preference'] as String,
        dietaryGoals:
            (map['dietary_goals'] as List<dynamic>? ?? []).cast<String>(),
        onboardingCompleted: map['onboarding_completed'] as bool,
      );
}

/// Talks directly to Supabase for onboarding reads/writes -- see
/// docs/architecture.md for why onboarding doesn't go through FastAPI.
class OnboardingRepository {
  // Looked up lazily so tests can subclass the repository without a
  // Supabase instance.
  SupabaseClient get _client => Supabase.instance.client;

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

  Future<List<String>> fetchDietaryExclusions() async {
    final rows = await _client
        .from('dietary_exclusions')
        .select('ingredient_name')
        .eq('user_id', _userId)
        .order('ingredient_name');
    return rows.map((row) => row['ingredient_name'] as String).toList();
  }

  Future<void> updateProfile({
    required int familySize,
    required double monthlyBudget,
    required String dietaryPreference,
    required List<String> dietaryGoals,
    required List<String> exclusions,
  }) async {
    await _client.from('onboarding_profiles').update({
      'family_size': familySize,
      'monthly_budget': monthlyBudget,
      'dietary_preference': dietaryPreference,
      'dietary_goals': dietaryGoals,
    }).eq('user_id', _userId);

    await _replaceExclusions(exclusions);
  }

  /// Saves everything collected on the single-page onboarding screen.
  ///
  /// Exclusions are written first and `onboarding_completed` is set last, in
  /// the same update as the household fields. If any step fails the user is
  /// not marked as onboarded, so tapping the button again simply retries.
  Future<void> saveOnboarding({
    required int familySize,
    required double monthlyBudget,
    required String dietaryPreference,
    required List<String> dietaryGoals,
    required List<String> exclusions,
  }) async {
    await _replaceExclusions(exclusions);

    await _client.from('onboarding_profiles').update({
      'family_size': familySize,
      'monthly_budget': monthlyBudget,
      'dietary_preference': dietaryPreference,
      'dietary_goals': dietaryGoals,
      'onboarding_completed': true,
      'onboarding_completed_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('user_id', _userId);
  }

  Future<void> _replaceExclusions(List<String> exclusions) async {
    final cleaned = cleanExclusions(exclusions);
    await _client.from('dietary_exclusions').delete().eq('user_id', _userId);
    if (cleaned.isNotEmpty) {
      await _client.from('dietary_exclusions').insert(
            cleaned
                .map((ingredient) => {
                      'user_id': _userId,
                      'ingredient_name': ingredient,
                    })
                .toList(),
          );
    }
  }
}

/// Trims, collapses spaces, drops blanks and removes case-insensitive
/// duplicates, keeping the first spelling the user entered.
List<String> cleanExclusions(Iterable<String> exclusions) {
  final cleaned = <String>[];
  final seen = <String>{};
  for (final exclusion in exclusions) {
    final value = exclusion.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (value.isNotEmpty && seen.add(value.toLowerCase())) cleaned.add(value);
  }
  return cleaned;
}
