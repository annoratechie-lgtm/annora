import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../state/onboarding_providers.dart';
import 'profile_saved_placeholder_screen.dart';

const _dietaryGoals = [
  ('keto', 'Keto'),
  ('diabetic_friendly', 'Diabetic-friendly'),
  ('high_protein', 'High protein'),
  ('low_sodium', 'Low sodium'),
  ('no_preference', 'No preference'),
];

class DietaryPreferencesScreen extends ConsumerStatefulWidget {
  const DietaryPreferencesScreen({super.key});

  @override
  ConsumerState<DietaryPreferencesScreen> createState() =>
      _DietaryPreferencesScreenState();
}

class _DietaryPreferencesScreenState
    extends ConsumerState<DietaryPreferencesScreen> {
  final _exclusionController = TextEditingController();
  final Set<String> _selectedGoals = {};
  final List<String> _exclusions = [];
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _exclusionController.dispose();
    super.dispose();
  }

  void _addExclusion() {
    final value = _exclusionController.text.trim();
    if (value.isEmpty) return;
    if (_exclusions.any((item) => item.toLowerCase() == value.toLowerCase())) {
      setState(() => _error = 'That ingredient is already in your list.');
      return;
    }
    setState(() {
      _exclusions.add(value);
      _exclusionController.clear();
      _error = null;
    });
  }

  Future<void> _finish() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(onboardingRepositoryProvider).completeOnboarding(
            dietaryGoals: _selectedGoals.toList(),
            exclusions: _exclusions,
          );
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ProfileSavedPlaceholderScreen()),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save -- $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              const Text('Step 2 of 2',
                  style: TextStyle(color: AppColors.textFaint, fontSize: 13)),
              const SizedBox(height: 8),
              Text('Food preferences',
                  style: AppTheme.displayFont.copyWith(
                      fontSize: 24, color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              const Text('Optional details that help tailor your recommendations.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
              const SizedBox(height: 32),
              const Text('Dietary goals',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _dietaryGoals.map((option) {
                  final selected = _selectedGoals.contains(option.$1);
                  return FilterChip(
                    label: Text(option.$2),
                    selected: selected,
                    onSelected: (isSelected) => setState(() {
                      isSelected
                          ? _selectedGoals.add(option.$1)
                          : _selectedGoals.remove(option.$1);
                    }),
                    backgroundColor: AppColors.card,
                    selectedColor: AppColors.orange,
                    labelStyle: TextStyle(
                        color: selected ? Colors.white : AppColors.textPrimary),
                    side: const BorderSide(color: AppColors.cardBorder),
                  );
                }).toList(),
              ),
              const SizedBox(height: 28),
              const Text('Dislikes or allergies',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
              const SizedBox(height: 4),
              const Text('Add ingredients you would rather avoid.',
                  style: TextStyle(color: AppColors.textFaint, fontSize: 12)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _exclusionController,
                    textCapitalization: TextCapitalization.sentences,
                    onSubmitted: (_) => _addExclusion(),
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'e.g. peanuts',
                      hintStyle: const TextStyle(color: AppColors.textFaint),
                      filled: true,
                      fillColor: AppColors.card,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.cardBorder),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _addExclusion,
                  icon: const Icon(Icons.add),
                  color: Colors.white,
                  style: IconButton.styleFrom(backgroundColor: AppColors.orange),
                ),
              ]),
              if (_exclusions.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _exclusions
                      .map((item) => InputChip(
                            label: Text(item),
                            onDeleted: () => setState(() => _exclusions.remove(item)),
                            backgroundColor: AppColors.card,
                            labelStyle: const TextStyle(color: AppColors.textPrimary),
                            deleteIconColor: AppColors.textMuted,
                            side: const BorderSide(color: AppColors.cardBorder),
                          ))
                      .toList(),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
              ],
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _saving ? null : _finish,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.orange,
                    disabledBackgroundColor: AppColors.card,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(26)),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Finish',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
