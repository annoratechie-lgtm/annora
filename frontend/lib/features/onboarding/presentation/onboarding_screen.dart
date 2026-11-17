import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../meal_plan/data/meal_plan_config.dart';
import '../../profile/data/user_profile_api.dart';
import '../state/onboarding_providers.dart';

/// Saves the user's name and phone (public `users` row, via the backend).
typedef SaveProfile = Future<void> Function(
    {required String name, String? phone});

const _diets = [
  ('vegetarian', 'Vegetarian', 'No meat, fish or eggs'),
  ('eggetarian', 'Eggetarian', 'Vegetarian + eggs'),
  ('non_vegetarian', 'Non-vegetarian', 'Meat, fish & eggs'),
  ('vegan', 'Vegan', 'Fully plant-based'),
  ('no_restriction', 'No restriction', 'We eat everything'),
];
const _budgets = [5000, 10000, 15000, 25000, 40000];
const _goals = [
  ('keto', 'Keto'),
  ('diabetic_friendly', 'Diabetic-friendly'),
  ('high_protein', 'High protein'),
  ('low_sodium', 'Low sodium'),
];
const _avoidPresets = [
  'Peanuts',
  'Mushroom',
  'Onion & garlic',
  'Gluten',
  'Dairy',
  'Seafood'
];

const _minFamily = 1;
const _maxFamily = 20; // matches the onboarding_profiles check constraint

const _field = Color(0xFF1A1411);
const _line = Color(0x17FFFFFF);
const _lineStrong = Color(0x29FFFFFF);
const _accentSoft = Color(0x26FF7A3D);
const _accentInk = Color(0xFFFFD9C4);
const _ok = Color(0xFF7BC47F);
const _error = Color(0xFFFF8A7A);

/// Single-page onboarding: name, phone, family size, diet, budget, goals and
/// foods to avoid. Everything is saved with one tap on the sticky button.
class OnboardingScreen extends ConsumerStatefulWidget {
  final SaveProfile? saveProfile;
  final VoidCallback? onCompleted;
  final String? initialName;

  const OnboardingScreen(
      {super.key, this.saveProfile, this.onCompleted, this.initialName});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _amount = TextEditingController();
  final _extra = TextEditingController();
  final _phoneFocus = FocusNode();

  int _family = 4;
  String? _diet;
  int? _budget;
  final Set<String> _goalKeys = {};
  final Set<String> _avoid = {};
  final List<String> _custom = [];

  bool _nameFromGoogle = false;
  bool _phoneTouched = false;
  String? _extraError;
  bool _saving = false;
  String? _saveError;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialName ?? _googleName();
    if (initial != null && initial.trim().isNotEmpty) {
      _name.text = initial.trim();
      _nameFromGoogle = true;
    }
    _phoneFocus.addListener(() {
      if (!_phoneFocus.hasFocus) setState(() => _phoneTouched = true);
    });
  }

  static String? _googleName() {
    try {
      final metadata =
          Supabase.instance.client.auth.currentUser?.userMetadata ?? const {};
      return (metadata['full_name'] ??
              metadata['name'] ??
              metadata['display_name'])
          ?.toString();
    } catch (_) {
      return null; // Supabase not initialised (tests)
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _amount.dispose();
    _extra.dispose();
    _phoneFocus.dispose();
    super.dispose();
  }

  // ---------- derived state ----------
  String get _phoneDigits => _phone.text.replaceAll(RegExp(r'\D'), '');
  bool get _phoneValid =>
      _phoneDigits.isEmpty || RegExp(r'^[6-9]\d{9}$').hasMatch(_phoneDigits);
  bool get _youDone => _name.text.trim().isNotEmpty && _phoneValid;
  bool get _dietDone => _diet != null;
  bool get _budgetDone => (_budget ?? 0) > 0;
  bool get _canSubmit => _youDone && _dietDone && _budgetDone;
  String? get _dietLabel =>
      _diets.where((d) => d.$1 == _diet).map((d) => d.$2).firstOrNull;

  String get _ctaLabel {
    final asks = <String>[];
    if (_name.text.trim().isEmpty) {
      asks.add('add your name');
    } else if (!_phoneValid) {
      asks.add('fix your mobile number');
    }
    final picks = [if (!_dietDone) 'a diet', if (!_budgetDone) 'a budget'];
    if (picks.isNotEmpty) asks.add('choose ${picks.join(' & ')}');
    final msg = asks.join(', ');
    return '${msg[0].toUpperCase()}${msg.substring(1)} to continue';
  }

  List<String> get _exclusions =>
      [..._avoidPresets.where(_avoid.contains), ..._custom];

  // ---------- actions ----------
  void _addExtra() {
    final value = _extra.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (value.isEmpty) return;
    final preset = _avoidPresets
        .where((p) => p.toLowerCase() == value.toLowerCase())
        .firstOrNull;
    setState(() {
      if (preset != null) {
        _avoid.add(preset);
        _extra.clear();
        _extraError = null;
      } else if (_custom.any((c) => c.toLowerCase() == value.toLowerCase())) {
        _extraError = '$value is already on your list.';
      } else {
        _custom.add(value);
        _extra.clear();
        _extraError = null;
      }
    });
  }

  Future<void> _submit() async {
    if (!_canSubmit || _saving) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final digits = _phoneDigits;
      await (widget.saveProfile ?? _defaultSaveProfile)(
        name: _name.text.trim(),
        phone: digits.isEmpty ? null : '+91$digits',
      );
      await ref.read(onboardingRepositoryProvider).saveOnboarding(
            familySize: _family,
            monthlyBudget: _budget!.toDouble(),
            dietaryPreference: _diet!,
            dietaryGoals: [
              for (final g in _goals)
                if (_goalKeys.contains(g.$1)) g.$1
            ],
            exclusions: _exclusions,
          );
      if (mounted) setState(() => _completed = true);
    } catch (e) {
      debugPrint('Onboarding save failed: $e');
      if (mounted) {
        setState(() => _saveError =
            "Couldn't save your answers. Check your connection and try again.");
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static Future<void> _defaultSaveProfile(
      {required String name, String? phone}) async {
    await UserProfileApi(baseUrl: mealPlanBackendUrl)
        .syncProfile(name: name, phone: phone);
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -1.2),
                  radius: 0.9,
                  colors: [Color(0x738A4A24), Color(0x008A4A24)],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: _completed
                    ? _buildReady()
                    : Column(
                        children: [Expanded(child: _buildForm()), _buildBar()]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    // A plain scrolling column (not a lazy ListView): six sections is short,
    // and keeping every field built avoids losing focus while scrolling.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Image.asset('assets/images/annora_mark.png',
                width: 64, semanticLabel: 'Annora'),
          ),
          const SizedBox(height: 12),
          Text.rich(
            const TextSpan(children: [
              TextSpan(text: "Let's set up your "),
              TextSpan(
                  text: 'kitchen', style: TextStyle(color: AppColors.orange)),
            ]),
            style: AppTheme.displayFont.copyWith(
                fontSize: 31, height: 1.08, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 8),
          const Text(
            'A few quick questions so Annora can plan meals your family will love.',
            style: TextStyle(
                color: AppColors.textMuted, fontSize: 14.5, height: 1.4),
          ),
          const SizedBox(height: 6),
          const Text('Takes under a minute · Change anytime in Profile',
              style: TextStyle(
                  color: AppColors.textFaint,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 22),
          _Section(
            number: 1,
            title: 'About you',
            done: _youDone,
            children: [
              _Labeled(
                label: 'Your name',
                child: _InputBox(
                  key: const Key('onboarding-name'),
                  controller: _name,
                  hint: 'Your name',
                  capitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() => _nameFromGoogle = false),
                  trailing: _nameFromGoogle
                      ? const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.check_rounded, size: 15, color: _ok),
                          SizedBox(width: 4),
                          Text('From Google',
                              style: TextStyle(
                                  color: AppColors.textFaint, fontSize: 12)),
                        ])
                      : null,
                ),
              ),
              _Labeled(
                label: 'Mobile number',
                optional: true,
                error: _phoneTouched && !_phoneValid
                    ? 'Enter a 10-digit Indian mobile number, or leave it blank.'
                    : null,
                child: _InputBox(
                  key: const Key('onboarding-phone'),
                  controller: _phone,
                  focusNode: _phoneFocus,
                  prefix: '+91',
                  hint: '98765 43210',
                  keyboardType: TextInputType.phone,
                  formatters: [_PhoneFormatter()],
                  invalid: _phoneTouched && !_phoneValid,
                  onChanged: (_) => setState(() => _phoneTouched = false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Section(
            number: 2,
            title: "Who's eating?",
            subtitle: 'Everyone who eats at home, including you.',
            done: true,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _RoundButton(
                    icon: Icons.remove_rounded,
                    tooltip: 'Fewer people',
                    onTap: _family > _minFamily
                        ? () => setState(() => _family--)
                        : null,
                  ),
                  Semantics(
                    liveRegion: true,
                    label: '$_family ${_family == 1 ? 'person' : 'people'}',
                    child: ExcludeSemantics(
                      child: Column(children: [
                        Text('$_family',
                            style: AppTheme.displayFont.copyWith(
                                fontSize: 46,
                                height: 1,
                                color: AppColors.textPrimary)),
                        Text(_family == 1 ? 'person' : 'people',
                            style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 13,
                                fontWeight: FontWeight.w500)),
                      ]),
                    ),
                  ),
                  _RoundButton(
                    icon: Icons.add_rounded,
                    tooltip: 'More people',
                    primary: true,
                    onTap: _family < _maxFamily
                        ? () => setState(() => _family++)
                        : null,
                  ),
                ],
              ),
              Center(
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  alignment: WrapAlignment.center,
                  children: List.generate(
                    _family,
                    (_) => Container(
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(
                          color: Color(0xD9FF7A3D), shape: BoxShape.circle),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Section(
            number: 3,
            title: 'What does your family eat?',
            subtitle: "We'll only suggest recipes that fit.",
            done: _dietDone,
            children: [
              LayoutBuilder(builder: (context, constraints) {
                final half = (constraints.maxWidth - 10) / 2;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (var i = 0; i < _diets.length; i++)
                      SizedBox(
                        width: i == _diets.length - 1
                            ? constraints.maxWidth
                            : half,
                        child: _DietCard(
                          label: _diets[i].$2,
                          description: _diets[i].$3,
                          selected: _diet == _diets[i].$1,
                          onTap: () => setState(() => _diet = _diets[i].$1),
                        ),
                      ),
                  ],
                );
              }),
            ],
          ),
          const SizedBox(height: 14),
          _Section(
            number: 4,
            title: 'Monthly grocery budget',
            subtitle: 'Helps us plan within budget and find cheaper swaps.',
            done: _budgetDone,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final b in _budgets)
                    _Pill(
                      label: b >= 40000 ? '₹40k+' : '₹${b ~/ 1000}k',
                      selected: _budget == b && _amount.text.isEmpty,
                      onTap: () => setState(() {
                        _budget =
                            (_budget == b && _amount.text.isEmpty) ? null : b;
                        _amount.clear();
                      }),
                    ),
                ],
              ),
              _Labeled(
                label: 'or enter an exact amount',
                child: _InputBox(
                  key: const Key('onboarding-amount'),
                  controller: _amount,
                  prefix: '₹',
                  hint: 'e.g. 12,000',
                  keyboardType: TextInputType.number,
                  formatters: [_RupeeFormatter()],
                  onChanged: (value) => setState(() {
                    final digits = value.replaceAll(RegExp(r'\D'), '');
                    _budget = digits.isEmpty ? null : int.parse(digits);
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Section(
            number: 5,
            title: 'Any health goals?',
            subtitle: 'Pick as many as you like.',
            optional: true,
            children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final g in _goals)
                  _ToggleChip(
                    label: g.$2,
                    selected: _goalKeys.contains(g.$1),
                    onTap: () => setState(() => _goalKeys.contains(g.$1)
                        ? _goalKeys.remove(g.$1)
                        : _goalKeys.add(g.$1)),
                  ),
              ]),
            ],
          ),
          const SizedBox(height: 14),
          _Section(
            number: 6,
            title: 'Anything to avoid?',
            subtitle: "Allergies or foods your family doesn't eat.",
            optional: true,
            children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final a in _avoidPresets)
                  _ToggleChip(
                    label: a,
                    selected: _avoid.contains(a),
                    onTap: () => setState(() =>
                        _avoid.contains(a) ? _avoid.remove(a) : _avoid.add(a)),
                  ),
                for (final c in _custom)
                  _ToggleChip(
                      label: c,
                      selected: true,
                      onRemove: () => setState(() => _custom.remove(c))),
              ]),
              _Labeled(
                label: 'Something else?',
                error: _extraError,
                child: _InputBox(
                  key: const Key('onboarding-extra'),
                  controller: _extra,
                  hint: 'Add an ingredient, e.g. brinjal',
                  capitalization: TextCapitalization.sentences,
                  maxLength: 40,
                  onChanged: (_) => setState(() => _extraError = null),
                  onSubmitted: (_) => _addExtra(),
                  trailing: _AddButton(
                      enabled: _extra.text.trim().isNotEmpty, onTap: _addExtra),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBar() {
    final required = [_youDone, true, _dietDone, _budgetDone];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: _line)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 12.5),
                  children: [
                    _bold('$_family'),
                    TextSpan(text: _family == 1 ? ' person' : ' people'),
                    if (_dietLabel != null) ...[
                      const TextSpan(text: ' · '),
                      _bold(_dietLabel!)
                    ],
                    if (_budgetDone) ...[
                      const TextSpan(text: ' · '),
                      _bold('₹${formatIndian(_budget!)}'),
                      const TextSpan(text: '/mo')
                    ],
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            Row(
              children: [
                for (final on in required)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(left: 4),
                    width: 18,
                    height: 4,
                    decoration: BoxDecoration(
                      color: on ? AppColors.orange : const Color(0x1FFFFFFF),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
              ],
            ),
          ]),
          const SizedBox(height: 10),
          if (_saveError != null) ...[
            Text(_saveError!,
                style: const TextStyle(color: _error, fontSize: 12.5),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              key: const Key('onboarding-submit'),
              onPressed: _canSubmit && !_saving ? _submit : null,
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: AppColors.orange,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    _saving ? AppColors.orange : AppColors.card,
                disabledForegroundColor:
                    _saving ? Colors.white : AppColors.textFaint,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                  side: _canSubmit || _saving
                      ? BorderSide.none
                      : const BorderSide(color: _line),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white))
                  : _canSubmit
                      ? const Row(mainAxisSize: MainAxisSize.min, children: [
                          Flexible(
                            child: Text('Start planning my meals',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 16)),
                          ),
                          SizedBox(width: 10),
                          Icon(Icons.arrow_forward_rounded, size: 19),
                        ])
                      : Text(_ctaLabel,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14)),
            ),
          ),
          const SizedBox(height: 8),
          const Text('You can change these anytime in Profile',
              style: TextStyle(color: AppColors.textFaint, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildReady() {
    final first = _name.text.trim().split(RegExp(r'\s+')).first;
    final pills = [
      '$_family ${_family == 1 ? 'person' : 'people'}',
      if (_dietLabel != null) _dietLabel!,
      if (_budgetDone) '₹${formatIndian(_budget!)} / month',
      for (final g in _goals)
        if (_goalKeys.contains(g.$1)) g.$2,
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 72, 24, 32),
      children: [
        Center(
            child: Image.asset('assets/images/annora_mark.png',
                width: 150, semanticLabel: 'Annora')),
        const SizedBox(height: 18),
        Text(
          'Your kitchen is ready, $first!',
          textAlign: TextAlign.center,
          style: AppTheme.displayFont.copyWith(
              fontSize: 29, height: 1.1, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 8),
        const Text(
          "We'll use this to plan meals that fit your family and budget.",
          textAlign: TextAlign.center,
          style: TextStyle(
              color: AppColors.textMuted, fontSize: 14.5, height: 1.4),
        ),
        const SizedBox(height: 18),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in pills)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0x0DFFFFFF),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _line),
                ),
                child: Text(p,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
              ),
          ],
        ),
        const SizedBox(height: 32),
        SizedBox(
          height: 56,
          child: ElevatedButton(
            key: const Key('onboarding-done'),
            onPressed: widget.onCompleted,
            style: ElevatedButton.styleFrom(
              elevation: 0,
              backgroundColor: AppColors.orange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28)),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                child: Text('Go to my kitchen',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              SizedBox(width: 10),
              Icon(Icons.arrow_forward_rounded, size: 19),
            ]),
          ),
        ),
      ],
    );
  }

  TextSpan _bold(String s) => TextSpan(
      text: s,
      style: const TextStyle(
          color: AppColors.textPrimary, fontWeight: FontWeight.w600));
}

/// 1234567 -> "12,34,567" (Indian digit grouping).
String formatIndian(int value) {
  final s = value.toString();
  if (s.length <= 3) return s;
  final last3 = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);
  final groups = <String>[];
  while (rest.length > 2) {
    groups.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) groups.insert(0, rest);
  return '${groups.join(',')},$last3';
}

class _RupeeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 7) digits = digits.substring(0, 7);
    digits = digits.replaceFirst(RegExp(r'^0+'), '');
    final text = digits.isEmpty ? '' : formatIndian(int.parse(digits));
    return TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

class _PhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 10) digits = digits.substring(0, 10);
    final text = digits.length > 5
        ? '${digits.substring(0, 5)} ${digits.substring(5)}'
        : digits;
    return TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

// ---------- building blocks ----------

class _Section extends StatelessWidget {
  final int number;
  final String title;
  final String? subtitle;
  final bool optional;
  final bool done;
  final List<Widget> children;

  const _Section({
    required this.number,
    required this.title,
    required this.children,
    this.subtitle,
    this.optional = false,
    this.done = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x12FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: done ? AppColors.orange : _accentSoft,
                  shape: BoxShape.circle),
              child: done
                  ? const Icon(Icons.check_rounded,
                      size: 15, color: Colors.white)
                  : Text('$number',
                      style: const TextStyle(
                          color: AppColors.orange,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(title,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
              ),
            ),
            if (optional) const _Tag('Optional'),
          ]),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle!,
                style:
                    const TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ],
          for (final child in children) ...[const SizedBox(height: 16), child],
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  const _Tag(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: const Color(0x0FFFFFFF),
          borderRadius: BorderRadius.circular(999)),
      child: Text(text,
          style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w500)),
    );
  }
}

class _Labeled extends StatelessWidget {
  final String label;
  final bool optional;
  final String? error;
  final Widget child;

  const _Labeled(
      {required this.label,
      required this.child,
      this.optional = false,
      this.error});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
          if (optional) ...[const SizedBox(width: 8), const _Tag('Optional')],
        ]),
        const SizedBox(height: 8),
        child,
        if (error != null) ...[
          const SizedBox(height: 6),
          Text(error!, style: const TextStyle(color: _error, fontSize: 12.5)),
        ],
      ],
    );
  }
}

class _InputBox extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final FocusNode? focusNode;
  final String? prefix;
  final Widget? trailing;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? formatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool invalid;
  final TextCapitalization capitalization;
  final int? maxLength;

  const _InputBox({
    super.key,
    required this.controller,
    required this.hint,
    this.focusNode,
    this.prefix,
    this.trailing,
    this.keyboardType,
    this.formatters,
    this.onChanged,
    this.onSubmitted,
    this.invalid = false,
    this.capitalization = TextCapitalization.none,
    this.maxLength,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.only(left: 16, right: 12),
      decoration: BoxDecoration(
        color: _field,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: invalid ? _error : const Color(0x14FFFFFF)),
      ),
      child: Row(children: [
        if (prefix != null) ...[
          Text(prefix!,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w500)),
          const SizedBox(width: 12),
          Container(width: 1, height: 22, color: _lineStrong),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            keyboardType: keyboardType,
            inputFormatters: [
              ...?formatters,
              if (maxLength != null)
                LengthLimitingTextInputFormatter(maxLength),
            ],
            textCapitalization: capitalization,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            cursorColor: AppColors.orange,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
              hintText: hint,
              hintStyle: const TextStyle(
                  color: AppColors.textFaint, fontWeight: FontWeight.w400),
            ),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ]),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool primary;

  const _RoundButton(
      {required this.icon,
      required this.tooltip,
      required this.onTap,
      this.primary = false});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final filled = primary && enabled;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: filled ? AppColors.orange : _field,
        shape: CircleBorder(
            side: filled ? BorderSide.none : const BorderSide(color: _line)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 52,
            height: 52,
            child: Icon(icon,
                size: 22,
                color: !enabled
                    ? const Color(0xFF4A403A)
                    : (filled ? Colors.white : AppColors.textPrimary)),
          ),
        ),
      ),
    );
  }
}

class _DietCard extends StatelessWidget {
  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  const _DietCard(
      {required this.label,
      required this.description,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: selected ? _accentSoft : const Color(0x08FFFFFF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: selected ? AppColors.orange : const Color(0x1AFFFFFF),
                  width: selected ? 1.5 : 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(label,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: selected ? AppColors.orange : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: selected
                              ? AppColors.orange
                              : const Color(0x38FFFFFF),
                          width: 1.5),
                    ),
                    child: selected
                        ? const Icon(Icons.check_rounded,
                            size: 13, color: Colors.white)
                        : null,
                  ),
                ]),
                const SizedBox(height: 4),
                Text(description,
                    style: TextStyle(
                        color: selected ? _accentInk : AppColors.textMuted,
                        fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Pill(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppColors.orange : const Color(0x08FFFFFF),
        shape: StadiumBorder(
            side: selected
                ? BorderSide.none
                : const BorderSide(color: _lineStrong)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(label,
                style: TextStyle(
                  color: selected ? Colors.white : AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                )),
          ),
        ),
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  const _ToggleChip(
      {required this.label, required this.selected, this.onTap, this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: onRemove != null ? 'Remove $label' : null,
      child: Material(
        color: selected ? _accentSoft : const Color(0x08FFFFFF),
        shape: StadiumBorder(
            side: BorderSide(color: selected ? AppColors.orange : _lineStrong)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onRemove ?? onTap,
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, 9, onRemove != null ? 8 : 15, 9),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(selected ? Icons.check_rounded : Icons.add_rounded,
                  size: 15,
                  color: selected ? AppColors.orange : AppColors.textFaint),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  )),
              if (onRemove != null) ...[
                const SizedBox(width: 6),
                Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                      color: Color(0x14FFFFFF), shape: BoxShape.circle),
                  child: const Icon(Icons.close_rounded,
                      size: 12, color: AppColors.textMuted),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;

  const _AddButton({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Add ingredient',
      child: Material(
        color: enabled ? AppColors.orange : const Color(0x14FFFFFF),
        shape: const CircleBorder(),
        child: InkWell(
          key: const Key('onboarding-extra-add'),
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: 30,
            height: 30,
            child: Icon(Icons.add_rounded,
                size: 18, color: enabled ? Colors.white : AppColors.textFaint),
          ),
        ),
      ),
    );
  }
}
