import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/annora_ui.dart';
import '../../onboarding/data/onboarding_repository.dart';
import '../../assistant/data/assistant_api.dart';
import '../data/user_profile_api.dart';
import 'memory_card.dart';

const _diets = [
  ('vegetarian', 'Vegetarian'),
  ('eggetarian', 'Eggetarian'),
  ('non_vegetarian', 'Non-vegetarian'),
  ('vegan', 'Vegan'),
  ('no_restriction', 'No restriction'),
];
const _goals = [
  ('keto', 'Keto'),
  ('diabetic_friendly', 'Diabetic-friendly'),
  ('high_protein', 'High protein'),
  ('low_sodium', 'Low sodium'),
];
const _budgets = [5000, 10000, 15000, 25000, 40000];
const _avoidPresets = [
  'Peanuts',
  'Mushroom',
  'Onion & garlic',
  'Gluten',
  'Dairy',
  'Seafood'
];
const _notifications = [
  ('meal_plan_updates', 'Meal plan updates', 'When a new week is ready'),
  ('grocery_reminders', 'Grocery reminders', 'Before your shopping day'),
  ('cooking_reminders', 'Cooking reminders', 'Before each planned meal'),
];

const supportEmail = 'annora.techie@gmail.com';
const supportPhone = '+91 9675866766';
const supportAddress =
    'Registered Office: Atal Center, BHU Varanasi, Uttar Pradesh – 221005, India';

/// "+91 98765 43210" style input -> "+919876543210", null when blank,
/// throws FormatException when it isn't a 10-digit Indian mobile number.
String? normalizeIndianMobile(String input) {
  var digits = input.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;
  if (digits.length == 12 && digits.startsWith('91'))
    digits = digits.substring(2);
  if (!RegExp(r'^[6-9]\d{9}$').hasMatch(digits)) {
    throw const FormatException(
        'Enter a 10-digit Indian mobile number, or leave it blank.');
  }
  return '+91$digits';
}

class ProfileScreen extends StatefulWidget {
  final UserProfileApi api;

  /// Shows "What Annora remembers" when set.
  final AssistantApi? assistantApi;
  final OnboardingRepository? repository;
  final bool isActive;
  final VoidCallback? onOpenHome;
  final VoidCallback? onOpenMealPlan;

  /// Overridable for tests (default: Supabase auth).
  final Future<void> Function()? signOut;
  final Future<void> Function(Map<String, dynamic> preferences)?
      saveNotifications;
  final Map<String, dynamic> Function()? readMetadata;
  final String? email;

  const ProfileScreen({
    super.key,
    required this.api,
    this.assistantApi,
    this.repository,
    this.isActive = true,
    this.onOpenHome,
    this.onOpenMealPlan,
    this.signOut,
    this.saveNotifications,
    this.readMetadata,
    this.email,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<void> _loading = _load();
  OnboardingProfile? _household;
  List<String> _exclusions = const [];
  String _name = '';
  String? _phone;
  Map<String, bool> _prefs = {};
  bool _confirmSignOut = false;
  bool _signingOut = false;

  OnboardingRepository get _repo => widget.repository ?? OnboardingRepository();

  @override
  void didUpdateWidget(covariant ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive && widget.isActive)
      setState(() {
        _loading = _load();
      });
  }

  Map<String, dynamic> _metadata() {
    if (widget.readMetadata != null) return widget.readMetadata!();
    try {
      return Map<String, dynamic>.from(
          Supabase.instance.client.auth.currentUser?.userMetadata ?? const {});
    } catch (_) {
      return {};
    }
  }

  String get _email {
    if (widget.email != null) return widget.email!;
    try {
      return Supabase.instance.client.auth.currentUser?.email ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> _load() async {
    final results = await Future.wait<Object?>([
      _repo.fetchProfile(),
      _repo.fetchDietaryExclusions(),
      widget.api.fetchProfile(),
    ]);
    _household = results[0] as OnboardingProfile?;
    _exclusions = results[1] as List<String>;
    final user = results[2] as Map<String, dynamic>;
    final meta = _metadata();
    _name = (user['name'] ?? meta['full_name'] ?? meta['name'] ?? '')
        .toString()
        .trim();
    final phone = user['phone']?.toString().trim();
    _phone = phone == null || phone.isEmpty ? null : phone;
    final raw = meta['notification_preferences'];
    _prefs = {
      for (final n in _notifications)
        n.$1: raw is Map ? raw[n.$1] != false : true,
    };
  }

  // ---------- saves ----------

  /// PUT /api/v1/users/me/profile {name, phone}.
  Future<void> _saveDetails(String name, String? phone) async {
    await widget.api.syncProfile(name: name, phone: phone);
    setState(() {
      _name = name;
      _phone = phone;
    });
    _snack('Saved');
  }

  /// onboarding_profiles + dietary_exclusions via OnboardingRepository.updateProfile.
  Future<void> _saveHousehold(_HouseholdDraft d) async {
    await _repo.updateProfile(
      familySize: d.people,
      monthlyBudget: d.budget!.toDouble(),
      dietaryPreference: d.diet,
      dietaryGoals: [
        for (final g in _goals)
          if (d.goals.contains(g.$1)) g.$1
      ],
      exclusions: d.avoid,
    );
    setState(() {
      _loading = _load();
    });
    _snack('Saved. Your next plan will use these.');
  }

  Future<void> _toggleNotification(String key) async {
    final next = Map<String, bool>.from(_prefs)..[key] = !(_prefs[key] ?? true);
    final previous = _prefs;
    setState(() => _prefs = next);
    try {
      if (widget.saveNotifications != null) {
        await widget.saveNotifications!(next);
      } else {
        final meta = _metadata()..['notification_preferences'] = next;
        await Supabase.instance.client.auth
            .updateUser(UserAttributes(data: meta));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _prefs = previous);
      _snack("Couldn't save that. Try again.");
    }
  }

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    try {
      await (widget.signOut ?? () => Supabase.instance.client.auth.signOut())();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _signingOut = false;
        _confirmSignOut = false;
      });
      _snack("Couldn't sign out: $e");
    }
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    _snack('Copied');
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------- sheets ----------

  Future<void> _openSheet(Widget child) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AnnoraUi.card,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
        builder: (context) => Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.88),
            child: child,
          ),
        ),
      );

  void _editDetails() => _openSheet(
      _DetailsSheet(name: _name, phone: _phone, onSave: _saveDetails));

  void _editHousehold() {
    final h = _household;
    if (h == null) return;
    _openSheet(_HouseholdSheet(
      initial: _HouseholdDraft(
        people: h.familySize,
        budget: h.monthlyBudget.round(),
        diet: h.dietaryPreference,
        goals: h.dietaryGoals.where((g) => g != 'no_preference').toSet(),
        avoid: List<String>.from(_exclusions),
      ),
      onSave: _saveHousehold,
    ));
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return AnnoraPage(
      child: FutureBuilder<void>(
        future: _loading,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.orange));
          }
          if (snap.hasError) {
            return EmptyState(
              icon: Icons.cloud_off_outlined,
              title: "Couldn't load your profile",
              body: '${snap.error}',
              action: 'Try again',
              onAction: () => setState(() {
                _loading = _load();
              }),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
            children: [
              const PageTitle(title: 'Profile'),
              const SizedBox(height: 16),
              _meCard(),
              const SizedBox(height: 14),
              if (_household != null) ...[
                _householdCard(_household!),
                const SizedBox(height: 14)
              ],
              if (widget.assistantApi != null) ...[
                MemoryCard(api: widget.assistantApi!),
                const SizedBox(height: 14),
              ],
              _notificationsCard(),
              const SizedBox(height: 14),
              _supportCard(),
              const SizedBox(height: 14),
              _accountCard(),
              const SizedBox(height: 16),
              const Center(
                  child: Text('Annora 0.1.0',
                      style: TextStyle(
                          color: AppColors.textFaint, fontSize: 12.5))),
            ],
          );
        },
      ),
    );
  }

  Widget _meCard() {
    final shownName = _name.isEmpty
        ? (_email.isEmpty ? 'Annora member' : _email.split('@').first)
        : _name;
    final initials = shownName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0])
        .join()
        .toUpperCase();
    return ACard(
      child: Row(children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: AppColors.avatarGold,
          child: Text(initials.isEmpty ? 'A' : initials,
              style: AppTheme.displayFont
                  .copyWith(fontSize: 22, color: AppColors.background)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(shownName,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            if (_email.isNotEmpty)
              Text(_email,
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 13.5)),
            if (_phone != null)
              Text(_prettyPhone(_phone!),
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 13.5))
            else
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: LinkButton(
                    label: 'Add a mobile number', onTap: _editDetails),
              ),
          ]),
        ),
        LinkButton(label: 'Edit', onTap: _editDetails),
      ]),
    );
  }

  Widget _householdCard(OnboardingProfile h) {
    final goals = _goals
        .where((g) => h.dietaryGoals.contains(g.$1))
        .map((g) => g.$2)
        .toList();
    final diet = _diets
        .firstWhere((d) => d.$1 == h.dietaryPreference,
            orElse: () => (h.dietaryPreference, h.dietaryPreference))
        .$2;
    return ACard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: _CardTitle('Household & food')),
          LinkButton(label: 'Edit', onTap: _editHousehold),
        ]),
        _row(Icons.groups_outlined, 'Household',
            '${h.familySize} ${h.familySize == 1 ? 'person' : 'people'}'),
        _row(Icons.account_balance_wallet_outlined, 'Monthly budget',
            '₹${_inr(h.monthlyBudget.round())}'),
        _row(Icons.eco_outlined, 'Diet', diet),
        _row(Icons.flag_outlined, 'Health goals',
            goals.isEmpty ? 'None' : goals.join(', ')),
        _row(Icons.block_outlined, 'Avoid',
            _exclusions.isEmpty ? 'Nothing' : _exclusions.join(', '),
            last: true),
        const SizedBox(height: 8),
        const Text('Changes apply to your next meal plan.',
            style: TextStyle(color: AppColors.textFaint, fontSize: 12.5)),
      ]),
    );
  }

  Widget _row(IconData icon, String label, String value, {bool last = false}) =>
      Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
            border: last
                ? null
                : const Border(bottom: BorderSide(color: AnnoraUi.line))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: AppColors.orange),
          const SizedBox(width: 12),
          Text(label,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 14)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
          ),
        ]),
      );

  Widget _notificationsCard() => ACard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _CardTitle('Notifications'),
          const SizedBox(height: 2),
          const Text(
              "Annora doesn't send these yet. Your choices are saved for when it does.",
              style: TextStyle(color: AppColors.textFaint, fontSize: 12.5)),
          for (final n in _notifications)
            SwitchListTile(
              key: Key('notif-${n.$1}'),
              contentPadding: EdgeInsets.zero,
              value: _prefs[n.$1] ?? true,
              onChanged: (_) => _toggleNotification(n.$1),
              activeThumbColor: Colors.white,
              activeTrackColor: AppColors.orange,
              inactiveTrackColor: const Color(0x24FFFFFF),
              title: Text(n.$2,
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 14.5)),
              subtitle: Text(n.$3,
                  style: const TextStyle(
                      color: AppColors.textFaint, fontSize: 12.5)),
            ),
        ]),
      );

  Widget _supportCard() => ACard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _CardTitle('Help & support'),
          _contact('Email', supportEmail),
          _contact('Phone', '+91 96758 66766', copyValue: supportPhone),
          _contact('Office', 'Atal Center, BHU, Varanasi, Uttar Pradesh 221005',
              copyValue: supportAddress, last: true),
        ]),
      );

  Widget _contact(String label, String value,
          {String? copyValue, bool last = false}) =>
      Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
            border: last
                ? null
                : const Border(bottom: BorderSide(color: AnnoraUi.line))),
        child: Row(children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: const TextStyle(
                      color: AppColors.textFaint, fontSize: 12)),
              SelectableText(value,
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 14)),
            ]),
          ),
          GhostButton(label: 'Copy', onTap: () => _copy(copyValue ?? value)),
        ]),
      );

  Widget _accountCard() => ACard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _CardTitle('Account'),
          if (_email.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text('Signed in with Google as $_email',
                style: const TextStyle(
                    color: AppColors.textFaint, fontSize: 12.5)),
          ],
          const SizedBox(height: 12),
          if (_confirmSignOut || _signingOut)
            ConfirmBox(
              message: 'Sign out of Annora on this device?',
              confirmLabel: 'Sign out',
              busy: _signingOut,
              onConfirm: _signOut,
              onCancel: () => setState(() => _confirmSignOut = false),
            )
          else
            GhostButton(
              key: const Key('sign-out'),
              label: 'Sign out',
              color: AnnoraUi.danger,
              onTap: () => setState(() => _confirmSignOut = true),
            ),
        ]),
      );

  static String _prettyPhone(String phone) {
    final d = phone.replaceAll(RegExp(r'\D'), '');
    if (d.length == 12 && d.startsWith('91'))
      return '+91 ${d.substring(2, 7)} ${d.substring(7)}';
    return phone;
  }
}

String _inr(int value) {
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

class _CardTitle extends StatelessWidget {
  final String text;
  const _CardTitle(this.text);

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 15.5,
          fontWeight: FontWeight.w600));
}

// ---------- details sheet ----------

class _DetailsSheet extends StatefulWidget {
  final String name;
  final String? phone;
  final Future<void> Function(String name, String? phone) onSave;
  const _DetailsSheet(
      {required this.name, required this.phone, required this.onSave});

  @override
  State<_DetailsSheet> createState() => _DetailsSheetState();
}

class _DetailsSheetState extends State<_DetailsSheet> {
  late final _name = TextEditingController(text: widget.name);
  late final _phone = TextEditingController(text: widget.phone ?? '');
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return setState(() => _error = 'Enter your name.');
    String? phone;
    try {
      phone = normalizeIndianMobile(_phone.text);
    } on FormatException catch (e) {
      return setState(() => _error = e.message);
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(name, phone);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = "Couldn't save: $e");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Your details',
                  style: AppTheme.displayFont
                      .copyWith(fontSize: 24, color: AppColors.textPrimary)),
              const SizedBox(height: 16),
              _SheetField(
                  key: const Key('details-name'),
                  label: 'Name',
                  controller: _name,
                  capitalization: TextCapitalization.words),
              const SizedBox(height: 14),
              _SheetField(
                key: const Key('details-phone'),
                label: 'Mobile number (optional)',
                controller: _phone,
                hint: '+91 98765 43210',
                keyboardType: TextInputType.phone,
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style: const TextStyle(
                        color: AnnoraUi.danger, fontSize: 12.5)),
              ],
              const SizedBox(height: 18),
              Row(children: [
                PrimaryButton(
                    key: const Key('details-save'),
                    label: 'Save',
                    busy: _saving,
                    onTap: _save),
                const SizedBox(width: 8),
                if (!_saving)
                  GhostButton(
                      label: 'Cancel',
                      onTap: () => Navigator.of(context).pop()),
              ]),
            ]),
      );
}

// ---------- household sheet ----------

class _HouseholdDraft {
  int people;
  int? budget;
  String diet;
  Set<String> goals;
  List<String> avoid;
  _HouseholdDraft(
      {required this.people,
      required this.budget,
      required this.diet,
      required this.goals,
      required this.avoid});
}

class _HouseholdSheet extends StatefulWidget {
  final _HouseholdDraft initial;
  final Future<void> Function(_HouseholdDraft draft) onSave;
  const _HouseholdSheet({required this.initial, required this.onSave});

  @override
  State<_HouseholdSheet> createState() => _HouseholdSheetState();
}

class _HouseholdSheetState extends State<_HouseholdSheet> {
  late final _HouseholdDraft d = widget.initial;
  late final _amount = TextEditingController(
      text: _budgets.contains(d.budget) || d.budget == null
          ? ''
          : _inr(d.budget!));
  final _extra = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _extra.dispose();
    super.dispose();
  }

  void _addExtra() {
    final v = _extra.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (v.isEmpty) return;
    setState(() {
      if (!d.avoid.any((a) => a.toLowerCase() == v.toLowerCase()))
        d.avoid.add(v);
      _extra.clear();
    });
  }

  Future<void> _save() async {
    if ((d.budget ?? 0) <= 0)
      return setState(() => _error = 'Choose or enter a monthly budget.');
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(d);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = "Couldn't save: $e");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _choice(String label, bool selected, VoidCallback onTap, {Key? key}) =>
      Semantics(
        button: true,
        selected: selected,
        child: Material(
          key: key,
          color: selected ? AppColors.orange : const Color(0x08FFFFFF),
          shape: StadiumBorder(
              side: selected
                  ? BorderSide.none
                  : const BorderSide(color: AnnoraUi.lineStrong)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
              child: Text(label,
                  style: TextStyle(
                      color: selected ? Colors.white : AppColors.textPrimary,
                      fontSize: 13.5,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w500)),
            ),
          ),
        ),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 16),
        child: Text(text,
            style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w500)),
      );

  @override
  Widget build(BuildContext context) {
    final presetAndCustom = [
      ..._avoidPresets,
      ...d.avoid.where((a) => !_avoidPresets.contains(a))
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Household & food',
                style: AppTheme.displayFont
                    .copyWith(fontSize: 24, color: AppColors.textPrimary)),
            _label('People who eat at home'),
            Row(children: [
              IconButton.outlined(
                tooltip: 'Fewer people',
                onPressed:
                    d.people > 1 ? () => setState(() => d.people--) : null,
                icon: const Icon(Icons.remove_rounded),
                color: AppColors.textPrimary,
              ),
              SizedBox(
                width: 56,
                child: Text('${d.people}',
                    key: const Key('house-people'),
                    textAlign: TextAlign.center,
                    style: AppTheme.displayFont
                        .copyWith(fontSize: 30, color: AppColors.textPrimary)),
              ),
              IconButton.filled(
                tooltip: 'More people',
                onPressed:
                    d.people < 20 ? () => setState(() => d.people++) : null,
                style: IconButton.styleFrom(
                    backgroundColor: AppColors.orange,
                    foregroundColor: Colors.white),
                icon: const Icon(Icons.add_rounded),
              ),
            ]),
            _label('Diet'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final diet in _diets)
                _choice(diet.$2, d.diet == diet.$1,
                    () => setState(() => d.diet = diet.$1)),
            ]),
            _label('Monthly grocery budget'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final b in _budgets)
                _choice(b >= 40000 ? '₹40k+' : '₹${b ~/ 1000}k',
                    d.budget == b && _amount.text.isEmpty, () {
                  setState(() {
                    d.budget = b;
                    _amount.clear();
                  });
                }),
            ]),
            const SizedBox(height: 10),
            _SheetField(
              key: const Key('house-amount'),
              label: 'or an exact amount',
              controller: _amount,
              hint: 'e.g. 12,000',
              keyboardType: TextInputType.number,
              prefix: '₹',
              onChanged: (v) {
                final digits = v.replaceAll(RegExp(r'\D'), '');
                setState(() => d.budget = digits.isEmpty
                    ? null
                    : int.parse(
                        digits.length > 7 ? digits.substring(0, 7) : digits));
              },
            ),
            _label('Health goals (optional)'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final g in _goals)
                _choice(
                    g.$2,
                    d.goals.contains(g.$1),
                    () => setState(() => d.goals.contains(g.$1)
                        ? d.goals.remove(g.$1)
                        : d.goals.add(g.$1))),
            ]),
            _label('Foods to avoid (optional)'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final a in presetAndCustom)
                _choice(
                    a,
                    d.avoid.contains(a),
                    () => setState(() => d.avoid.contains(a)
                        ? d.avoid.remove(a)
                        : d.avoid.add(a))),
            ]),
            const SizedBox(height: 10),
            _SheetField(
              key: const Key('house-extra'),
              label: 'Something else?',
              controller: _extra,
              hint: 'Add an ingredient and press Enter',
              onSubmitted: (_) => _addExtra(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style:
                      const TextStyle(color: AnnoraUi.danger, fontSize: 12.5)),
            ],
            const SizedBox(height: 18),
            Row(children: [
              PrimaryButton(
                  key: const Key('house-save'),
                  label: 'Save',
                  busy: _saving,
                  onTap: _save),
              const SizedBox(width: 8),
              if (!_saving)
                GhostButton(
                    label: 'Cancel', onTap: () => Navigator.of(context).pop()),
            ]),
          ]),
    );
  }
}

class _SheetField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? prefix;
  final TextInputType? keyboardType;
  final TextCapitalization capitalization;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  const _SheetField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.prefix,
    this.keyboardType,
    this.capitalization = TextCapitalization.none,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          textCapitalization: capitalization,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          cursorColor: AppColors.orange,
          style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.textFaint),
            prefixText: prefix == null ? null : '$prefix ',
            prefixStyle:
                const TextStyle(color: AppColors.textPrimary, fontSize: 15),
            filled: true,
            fillColor: AnnoraUi.field,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AnnoraUi.line)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AnnoraUi.line)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.orange)),
          ),
        ),
      ]);
}
