import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../profile/data/user_profile_api.dart';
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
  final UserProfileApi? profileApi;

  const HouseholdBasicsScreen({super.key, this.profileApi});

  @override
  ConsumerState<HouseholdBasicsScreen> createState() => _HouseholdBasicsScreenState();
}

class _HouseholdBasicsScreenState extends ConsumerState<HouseholdBasicsScreen> {
  int _familySize = 4;
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _budgetController = TextEditingController();
  String? _dietaryPreference;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final metadata =
        Supabase.instance.client.auth.currentUser?.userMetadata ?? const {};
    _nameController.text = (metadata['full_name'] ??
            metadata['name'] ??
            metadata['display_name'])
        ?.toString() ??
        '';
    _phoneController.text = metadata['contact_phone']?.toString() ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _budgetController.dispose();
    super.dispose();
  }

  bool get _canContinue {
    final budget = double.tryParse(_budgetController.text);
    final phone = _phoneController.text.trim();
    final validPhone = phone.isEmpty ||
        RegExp(r'^\+?[0-9\s()-]{7,20}$').hasMatch(phone);
    return _nameController.text.trim().isNotEmpty &&
        validPhone &&
        _dietaryPreference != null &&
        budget != null &&
        budget > 0;
  }

  Future<void> _onContinue() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(onboardingRepositoryProvider).saveHouseholdBasics(
            name: _nameController.text.trim(),
            phone: _phoneController.text.trim().isEmpty
                ? null
                : _phoneController.text.trim(),
            familySize: _familySize,
            monthlyBudget: double.parse(_budgetController.text),
            dietaryPreference: _dietaryPreference!,
          );
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => DietaryPreferencesScreen(api: widget.profileApi),
          ),
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
              const Text('Step 1 of 2', style: TextStyle(color: AppColors.textFaint, fontSize: 13)),
              const SizedBox(height: 8),
              Text(
                'Tell us about your household',
                style: AppTheme.displayFont.copyWith(fontSize: 24, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 32),

              const Text('Your name', style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                style: const TextStyle(color: AppColors.textPrimary),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'e.g. Alex Morgan',
                  hintStyle: const TextStyle(color: AppColors.textFaint),
                  filled: true,
                  fillColor: AppColors.card,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.cardBorder),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              const Text('Mobile number (optional)', style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
              const SizedBox(height: 8),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                style: const TextStyle(color: AppColors.textPrimary),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: '+91 98765 43210',
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
