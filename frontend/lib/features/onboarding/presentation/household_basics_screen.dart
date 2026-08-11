import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../state/onboarding_providers.dart';
import 'dietary_preferences_screen.dart';

const _dietaryPreferences = [
  ('vegetarian', 'Vegetarian'),
  ('eggetarian', 'Eggetarian'),
  ('non_vegetarian', 'Non-vegetarian'),
  ('vegan', 'Vegan'),
  ('no_restriction', 'No restriction'),
];

class HouseholdBasicsScreen extends ConsumerStatefulWidget {
  const HouseholdBasicsScreen({super.key});

  @override
  ConsumerState<HouseholdBasicsScreen> createState() => _HouseholdBasicsScreenState();
}

class _HouseholdBasicsScreenState extends ConsumerState<HouseholdBasicsScreen> {
  int _familySize = 4;
  final _budgetController = TextEditingController();
  String? _dietaryPreference;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _budgetController.dispose();
    super.dispose();
  }

  bool get _canContinue {
    final budget = double.tryParse(_budgetController.text);
    return _dietaryPreference != null && budget != null && budget > 0;
  }

  Future<void> _onContinue() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(onboardingRepositoryProvider).saveHouseholdBasics(
            familySize: _familySize,
            monthlyBudget: double.parse(_budgetController.text),
            dietaryPreference: _dietaryPreference!,
          );
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DietaryPreferencesScreen()),
        );
      }
    } catch (e) {
      setState(() => _error = 'Could not save -- $e');
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
              const Text('Step 1 of 2', style: TextStyle(color: AppColors.textFaint, fontSize: 13)),
              const SizedBox(height: 8),
              Text(
                'Tell us about your household',
                style: AppTheme.displayFont.copyWith(fontSize: 24, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 32),

              const Text('Family size', style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _StepperButton(
                    icon: Icons.remove,
                    onTap: _familySize > 1 ? () => setState(() => _familySize--) : null,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text('$_familySize', style: const TextStyle(color: AppColors.textPrimary, fontSize: 20)),
                  ),
                  _StepperButton(
                    icon: Icons.add,
                    onTap: _familySize < 20 ? () => setState(() => _familySize++) : null,
                  ),
                ],
              ),
              const SizedBox(height: 24),

              const Text('Monthly grocery budget', style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
              const SizedBox(height: 8),
              TextField(
                controller: _budgetController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: AppColors.textPrimary),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  prefixText: '₹ ',
                  prefixStyle: const TextStyle(color: AppColors.textPrimary),
                  hintText: 'e.g. 15000',
                  hintStyle: const TextStyle(color: AppColors.textFaint),
                  filled: true,
                  fillColor: AppColors.card,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.cardBorder),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              const Text('Dietary preference', style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _dietaryPreferences.map((option) {
                  final selected = _dietaryPreference == option.$1;
                  return ChoiceChip(
                    label: Text(option.$2),
                    selected: selected,
                    onSelected: (_) => setState(() => _dietaryPreference = option.$1),
                    backgroundColor: AppColors.card,
                    selectedColor: AppColors.orange,
                    labelStyle: TextStyle(color: selected ? Colors.white : AppColors.textPrimary),
                    side: const BorderSide(color: AppColors.cardBorder),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
              ],

              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: (_canContinue && !_saving) ? _onContinue : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.orange,
                    disabledBackgroundColor: AppColors.card,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Continue', style: TextStyle(fontWeight: FontWeight.w700)),
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

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _StepperButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.card,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Icon(icon, color: onTap == null ? AppColors.textFaint : AppColors.textPrimary, size: 18),
      ),
    );
  }
}
